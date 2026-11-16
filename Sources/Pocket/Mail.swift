import AppKit
import CryptoKit
import Network
import Security

let googleSession = URLSession(configuration: .ephemeral)

enum Keychain {
    static let service = "com.pranav.pocket.gmail"

    static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    @discardableResult
    static func set(_ account: String, _ value: String) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        var add = base(account)
        add[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { note("pocket keychain write failed account=\(account) status=\(status)") }
        return status == errSecSuccess
    }

    static func get(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound { note("pocket keychain read failed account=\(account) status=\(status)") }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

func formBody(_ fields: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
}

func googleCall(_ url: URL, form: [String: String]? = nil, bearer: String? = nil, done: @escaping (Int, [String: Any]?) -> Void) {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    if let form {
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(form)
    }
    if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    googleSession.dataTask(with: request) { data, response, error in
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let error { note("pocket google call failed host=\(url.host ?? "-") path=\(url.path) cause=\(error.localizedDescription)") }
        DispatchQueue.main.async { done(status, json) }
    }.resume()
}

final class GoogleAuth {
    static let scope = "https://mail.google.com/"
    let clientId: String
    let clientSecret: String
    var listeners: [ObjectIdentifier: NWListener] = [:]

    init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    static func load() -> GoogleAuth? {
        let path = NSHomeDirectory() + "/Library/Application Support/Pocket/google-client.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = json["id"], let secret = json["secret"] else {
            note("pocket gmail client config missing path=\(path)")
            return nil
        }
        return GoogleAuth(clientId: id, clientSecret: secret)
    }

    static func urlSafe(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func refresh(_ token: String, done: @escaping (String?, TimeInterval, String) -> Void) {
        googleCall(URL(string: "https://oauth2.googleapis.com/token")!,
                   form: ["client_id": clientId, "client_secret": clientSecret, "refresh_token": token, "grant_type": "refresh_token"]) { status, json in
            if let access = json?["access_token"] as? String {
                done(access, (json?["expires_in"] as? Double) ?? 3600, "")
            } else {
                done(nil, 0, (json?["error"] as? String) ?? "status \(status)")
            }
        }
    }

    func signIn(copyLink: Bool, done: @escaping (String?, String?, TimeInterval) -> Void) {
        let verifier = GoogleAuth.urlSafe(Data((0..<48).map { _ in UInt8.random(in: 0...255) }))
        let challenge = GoogleAuth.urlSafe(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: params) else {
            note("pocket gmail sign-in failed stage=listen")
            return done(nil, nil, 0)
        }
        let key = ObjectIdentifier(listener)
        listeners[key] = listener
        DispatchQueue.main.asyncAfter(deadline: .now() + 900) { [weak self] in
            guard let self, self.listeners.removeValue(forKey: key) != nil else { return }
            listener.cancel()
            note("pocket gmail sign-in expired port=\(listener.port?.rawValue ?? 0)")
        }
        var redirect = ""
        var finished = false
        listener.stateUpdateHandler = { [weak self] st in
            guard let self, case .ready = st, let port = listener.port?.rawValue else { return }
            redirect = "http://127.0.0.1:\(port)"
            var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            parts.queryItems = [
                URLQueryItem(name: "client_id", value: self.clientId), URLQueryItem(name: "redirect_uri", value: redirect),
                URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "scope", value: GoogleAuth.scope),
                URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state), URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "select_account consent"),
            ]
            note("pocket gmail sign-in started port=\(port) via=\(copyLink ? "copied link" : "default browser")")
            if copyLink {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(parts.url!.absoluteString, forType: .string)
            } else {
                NSWorkspace.shared.open(parts.url!)
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                guard let self, let data, let first = String(decoding: data, as: UTF8.self).split(separator: "\r\n").first else { return conn.cancel() }
                let target = first.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                note("pocket gmail sign-in callback port=\(listener.port?.rawValue ?? 0) path=\(target.split(separator: "?").first ?? "-") hasCode=\(target.contains("code="))")
                let items = URLComponents(string: "http://x" + target)?.queryItems ?? []
                let code = items.first { $0.name == "code" }?.value
                let failure = items.first { $0.name == "error" }?.value
                guard code != nil || failure != nil else {
                    conn.send(content: Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in conn.cancel() })
                    return
                }
                let ok = code != nil && items.first { $0.name == "state" }?.value == state
                let page = ok ? "Pocket is signed in to Gmail. You can close this tab." : "Pocket sign-in did not finish. You can close this tab and try again."
                conn.send(content: Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body style=\"font:16px -apple-system;padding:48px\">\(page)</body></html>".utf8),
                          completion: .contentProcessed { _ in conn.cancel() })
                if finished { return }
                finished = true
                self.listeners.removeValue(forKey: key)
                listener.cancel()
                guard ok, let code else {
                    note("pocket gmail sign-in refused cause=\(failure ?? "state mismatch")")
                    return done(nil, nil, 0)
                }
                googleCall(URL(string: "https://oauth2.googleapis.com/token")!,
                           form: ["code": code, "client_id": self.clientId, "client_secret": self.clientSecret, "redirect_uri": redirect,
                                  "grant_type": "authorization_code", "code_verifier": verifier]) { status, json in
                    let refresh = json?["refresh_token"] as? String
                    let access = json?["access_token"] as? String
                    if refresh == nil || access == nil {
                        note("pocket gmail token exchange failed status=\(status) cause=\((json?["error"] as? String) ?? "-")")
                    }
                    done(refresh, access, (json?["expires_in"] as? Double) ?? 3600)
                }
            }
        }
        listener.start(queue: .main)
    }
}

final class MailAccount {
    enum Phase { case closed, greeting, auth, examine, idle, done, fetch }

    let email: String
    let auth: GoogleAuth
    let found: (String, String) -> Void
    var access = ""
    var expires = Date.distantPast
    var connection: NWConnection?
    var buffer = Data()
    var phase = Phase.closed
    var tag = 0
    var current = ""
    var uidNext: UInt32 = 0
    var lastUid: UInt32 = 0
    var fetched: [(UInt32, String)] = []
    var generation = 0
    var backoff: TimeInterval = 5
    var retrying = false
    var stopped = false
    var idleTimer: Timer?
    var pollTimer: Timer?
    var seen = Set<String>()
    var primed = false
    var pollFailing = false

    init(email: String, auth: GoogleAuth, found: @escaping (String, String) -> Void) {
        self.email = email
        self.auth = auth
        self.found = found
    }

    func start() {
        withToken { [weak self] in self?.connect() }
        guard pollTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 5
        pollTimer = timer
        poll()
    }

    func stop() {
        stopped = true
        generation += 1
        idleTimer?.invalidate()
        idleTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        connection?.cancel()
        connection = nil
        phase = .closed
        note("pocket gmail account stopped account=\(email)")
    }

    func poll() {
        guard !stopped else { return }
        withToken { [weak self] in
            guard let self else { return }
            var parts = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
            parts.queryItems = [URLQueryItem(name: "labelIds", value: "INBOX"), URLQueryItem(name: "q", value: "newer_than:1d"), URLQueryItem(name: "maxResults", value: "10")]
            googleCall(parts.url!, bearer: self.access) { [weak self] status, json in
                guard let self else { return }
                guard status == 200, let json else {
                    if !self.pollFailing { note("pocket gmail poll failed account=\(self.email) status=\(status) cause=\(((json?["error"] as? [String: Any])?["message"] as? String) ?? "-")") }
                    self.pollFailing = true
                    return
                }
                if self.pollFailing { note("pocket gmail poll recovered account=\(self.email)") }
                self.pollFailing = false
                let ids = ((json["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
                let fresh = ids.filter { !self.seen.contains($0) }
                if !self.primed {
                    self.primed = true
                    self.seen.formUnion(ids)
                    note("pocket gmail poll primed account=\(self.email) known=\(ids.count)")
                    fresh.prefix(5).forEach { self.look(at: $0, via: "baseline") }
                    return
                }
                fresh.forEach { self.look(at: $0, via: "poll") }
            }
        }
    }

    func restart(reason: String) {
        note("pocket gmail reconnecting account=\(email) reason=\(reason)")
        backoff = 5
        retrying = false
        start()
    }

    func withToken(_ next: @escaping () -> Void) {
        if !access.isEmpty && expires.timeIntervalSinceNow > 300 { return next() }
        guard let refresh = Keychain.get(email) else {
            stopped = true
            return note("pocket gmail needs sign-in account=\(email) cause=no refresh token")
        }
        auth.refresh(refresh) { [weak self] token, life, error in
            guard let self else { return }
            guard let token else {
                note("pocket gmail token refresh failed account=\(self.email) cause=\(error)")
                if error == "invalid_grant" {
                    self.stopped = true
                    return note("pocket gmail needs sign-in account=\(self.email) cause=refresh token revoked")
                }
                return self.retryLater(reason: "token refresh")
            }
            self.access = token
            self.expires = Date().addingTimeInterval(life)
            next()
        }
    }

    func connect() {
        generation += 1
        let gen = generation
        connection?.cancel()
        idleTimer?.invalidate()
        buffer.removeAll()
        phase = .greeting
        let conn = NWConnection(host: "imap.gmail.com", port: 993, using: .tls)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self, gen == self.generation else { return }
            switch state {
            case .failed(let error): self.retryLater(reason: "connection failed \(error)")
            case .waiting(let error): self.retryLater(reason: "connection waiting \(error)")
            default: break
            }
        }
        connection = conn
        conn.start(queue: .main)
        receive(conn, gen)
    }

    func receive(_ conn: NWConnection, _ gen: Int) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, gen == self.generation else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if complete || error != nil { return self.retryLater(reason: "server closed \(error.map { "\($0)" } ?? "-")") }
            self.receive(conn, gen)
        }
    }

    func drain() {
        let crlf = Data("\r\n".utf8)
        while let end = buffer.range(of: crlf) {
            let line = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
            buffer = Data(buffer[end.upperBound...])
            handle(line)
        }
    }

    func send(_ command: String) {
        tag += 1
        current = "p\(tag)"
        write("\(current) \(command)\r\n")
    }

    func write(_ text: String) {
        connection?.send(content: Data(text.utf8), completion: .contentProcessed { [email] error in
            if let error { note("pocket gmail write failed account=\(email) cause=\(error)") }
        })
    }

    func tagged(_ line: String) -> String? {
        guard line.hasPrefix(current + " ") else { return nil }
        return String(line.dropFirst(current.count + 1).prefix(3)).trimmingCharacters(in: .whitespaces)
    }

    func handle(_ line: String) {
        switch phase {
        case .greeting:
            guard line.hasPrefix("* OK") else { return }
            phase = .auth
            send("AUTHENTICATE XOAUTH2 " + Data("user=\(email)\u{1}auth=Bearer \(access)\u{1}\u{1}".utf8).base64EncodedString())
        case .auth:
            if line.hasPrefix("+") { return write("\r\n") }
            guard let result = tagged(line) else { return }
            guard result == "OK" else {
                access = ""
                return retryLater(reason: "login rejected")
            }
            phase = .examine
            send("EXAMINE INBOX")
        case .examine:
            if let range = line.range(of: "[UIDNEXT "), let value = UInt32(line[range.upperBound...].prefix { $0.isNumber }) { uidNext = value }
            guard let result = tagged(line) else { return }
            guard result == "OK" else { return retryLater(reason: "inbox refused") }
            if lastUid == 0 { lastUid = uidNext &- 1 }
            backoff = 5
            note("pocket gmail watching account=\(email) fromUid=\(lastUid)")
            uidNext &- 1 > lastUid ? fetchNew() : idle()
        case .idle:
            if line.hasPrefix("* "), line.hasSuffix(" EXISTS") { stopIdle() }
        case .done:
            if tagged(line) != nil { fetchNew() }
        case .fetch:
            if line.hasPrefix("* "), line.contains("FETCH"),
               let uid = MailAccount.number(after: "UID ", in: line), let gm = MailAccount.number(after: "X-GM-MSGID ", in: line),
               let uidValue = UInt32(uid), uidValue > lastUid, let gmValue = UInt64(gm) {
                fetched.append((uidValue, String(gmValue, radix: 16)))
            }
            guard tagged(line) != nil else { return }
            let batch = fetched
            fetched.removeAll()
            lastUid = max(lastUid, batch.map(\.0).max() ?? 0)
            batch.forEach { look(at: $0.1, via: "idle") }
            idle()
        case .closed:
            break
        }
    }

    static func number(after key: String, in line: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    func idle() {
        phase = .idle
        send("IDLE")
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: false) { [weak self] _ in
            guard let self, self.phase == .idle else { return }
            if self.expires.timeIntervalSinceNow < 600 { return self.restart(reason: "token renewal") }
            self.stopIdle()
        }
    }

    func stopIdle() {
        idleTimer?.invalidate()
        phase = .done
        write("DONE\r\n")
    }

    func fetchNew() {
        phase = .fetch
        send("UID FETCH \(lastUid + 1):* (UID X-GM-MSGID)")
    }

    func look(at id: String, via: String) {
        if via != "baseline" {
            guard !seen.contains(id) else { return }
            seen.insert(id)
        }
        var parts = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        parts.queryItems = [URLQueryItem(name: "format", value: "metadata"), URLQueryItem(name: "metadataHeaders", value: "Subject"),
                            URLQueryItem(name: "metadataHeaders", value: "From")]
        googleCall(parts.url!, bearer: access) { [weak self] status, json in
            guard let self else { return }
            guard status == 200, let json else {
                return note("pocket gmail message read failed account=\(self.email) id=\(id) status=\(status) cause=\(((json?["error"] as? [String: Any])?["message"] as? String) ?? "-")")
            }
            let headers = ((json["payload"] as? [String: Any])?["headers"] as? [[String: String]]) ?? []
            let subject = headers.first { $0["name"] == "Subject" }?["value"] ?? ""
            let from = headers.first { $0["name"] == "From" }?["value"] ?? ""
            let domain = from.split(separator: "@").last.map { String($0.prefix { $0 != ">" && $0 != " " }) } ?? "-"
            let snippet = MailAccount.plain((json["snippet"] as? String) ?? "")
            let sent = Double((json["internalDate"] as? String) ?? "").map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            let lag = Int(Date().timeIntervalSince(sent))
            let code = lag < 600 ? OtpWatcher.extract(subject + "\n" + snippet) : nil
            note("pocket gmail message checked account=\(self.email) id=\(id) via=\(via) fromDomain=\(domain) lagSeconds=\(lag) hasCode=\(code != nil)")
            if let code, via != "baseline" { self.found(code, "gmail account=\(self.email) id=\(id) fromDomain=\(domain)") }
        }
    }

    static func plain(_ text: String) -> String {
        [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    func retryLater(reason: String) {
        generation += 1
        connection?.cancel()
        connection = nil
        idleTimer?.invalidate()
        phase = .closed
        if retrying || stopped { return }
        retrying = true
        let wait = backoff
        backoff = min(backoff * 2, 120)
        note("pocket gmail disconnected account=\(email) reason=\(reason) retryIn=\(Int(wait))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.retrying = false
            self.start()
        }
    }
}

final class MailWatcher: NSObject {
    let otp: OtpWatcher
    let auth = GoogleAuth.load()
    var accounts: [MailAccount] = []
    var wakeObserver: NSObjectProtocol?

    var available: Bool { auth != nil }

    init(otp: OtpWatcher) { self.otp = otp }

    var saved: [String] {
        get { UserDefaults.standard.stringArray(forKey: "gmailAccounts") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "gmailAccounts") }
    }

    func start() {
        guard let auth else { return }
        accounts = saved.map { account(email: $0, auth: auth) }
        accounts.forEach { $0.start() }
        note("pocket gmail started accounts=\(accounts.count)")
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.accounts.forEach { $0.restart(reason: "mac woke") }
        }
    }

    func stop() {
        accounts.forEach { $0.stop() }
        accounts.removeAll()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        note("pocket gmail stopped")
    }

    func account(email: String, auth: GoogleAuth) -> MailAccount {
        MailAccount(email: email, auth: auth) { [weak self] code, source in self?.otp.show(code, source: source) }
    }

    @objc func addAccount() { signIn(copyLink: false) }

    @objc func copySignInLink() { signIn(copyLink: true) }

    func signIn(copyLink: Bool) {
        guard let auth else { return note("pocket gmail sign-in skipped cause=no client config") }
        auth.signIn(copyLink: copyLink) { [weak self] refresh, access, life in
            guard let self, let refresh, let access else { return }
            googleCall(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!, bearer: access) { status, json in
                guard let email = json?["emailAddress"] as? String else {
                    return note("pocket gmail profile failed status=\(status) cause=\(((json?["error"] as? [String: Any])?["message"] as? String) ?? "-")")
                }
                guard Keychain.set(email, refresh) else { return }
                self.accounts.first { $0.email == email }?.retryLater(reason: "replaced")
                self.accounts.removeAll { $0.email == email }
                let account = self.account(email: email, auth: auth)
                account.access = access
                account.expires = Date().addingTimeInterval(life)
                self.accounts.append(account)
                if !self.saved.contains(email) { self.saved.append(email) }
                note("pocket gmail account added account=\(email) total=\(self.accounts.count)")
                account.start()
            }
        }
    }
}
