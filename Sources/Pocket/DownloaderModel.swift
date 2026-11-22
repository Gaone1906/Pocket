import AppKit
import Foundation
import UserNotifications

struct DownloadItem: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let total: Int64
    let done: Int64
    let speed: Int64
    let error: String?
    let path: String?

    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var running: Bool { status == "active" || status == "waiting" }
    var finished: Bool { status == "complete" || status == "error" || status == "removed" }
}

final class DownloaderModel: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var problem: String?
    var onChange: (() -> Void)?

    private let port = 6809
    private let secret = UUID().uuidString
    private var process: Process?
    private var timer: Timer?
    private var known: [String: String] = [:]
    private var awake: NSObjectProtocol?
    private let session = URLSession(configuration: .ephemeral)

    static let downloads = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
    private static var folder: URL { PocketData.root.appendingPathComponent("Downloader", isDirectory: true) }
    private static var sessionFile: URL { folder.appendingPathComponent("aria2.session") }

    static func binary() -> String? {
        ["/opt/homebrew/bin/aria2c", "/usr/local/bin/aria2c", "/usr/bin/aria2c"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var percent: Int? {
        let live = items.filter { $0.running && $0.total > 0 }
        guard !live.isEmpty else { return nil }
        let total = live.reduce(Int64(0)) { $0 + $1.total }
        let done = live.reduce(Int64(0)) { $0 + $1.done }
        return Int((Double(done) / Double(total) * 100).rounded(.down))
    }

    func start() {
        guard process == nil else { return }
        guard let binary = Self.binary() else {
            problem = "aria2 isn't installed. Run: brew install aria2"
            note("downloader aria2 missing searched=/opt/homebrew/bin,/usr/local/bin,/usr/bin")
            return
        }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var args = [
            "--enable-rpc", "--rpc-listen-port=\(port)", "--rpc-secret=\(secret)",
            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
            "--dir=\(Self.downloads.path)", "--continue=true", "--auto-file-renaming=false",
            "--max-connection-per-server=4", "--split=4", "--min-split-size=20M",
            "--max-tries=0", "--retry-wait=5", "--timeout=60", "--connect-timeout=30",
            "--file-allocation=none", "--max-concurrent-downloads=3",
            "--save-session=\(Self.sessionFile.path)", "--save-session-interval=15",
            "--quiet=true", "--summary-interval=0",
        ]
        if FileManager.default.fileExists(atPath: Self.sessionFile.path) { args.append("--input-file=\(Self.sessionFile.path)") }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let errors = Pipe()
        proc.standardError = errors
        proc.standardOutput = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] done in
            let tail = String(data: errors.fileHandleForReading.availableData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " | ") ?? ""
            note("downloader aria2 exited status=\(done.terminationStatus) reason=\(done.terminationReason.rawValue) stderr=\(tail.prefix(400))")
            DispatchQueue.main.async {
                guard let self, self.process === done else { return }
                self.process = nil
                self.problem = "aria2 stopped (status \(done.terminationStatus)). Reopen Downloader to restart it."
                self.publish()
            }
        }
        do {
            try proc.run()
            process = proc
            problem = nil
            note("downloader aria2 started pid=\(proc.processIdentifier) port=\(port) binary=\(binary) resumed=\(args.contains { $0.hasPrefix("--input-file") })")
        } catch {
            problem = "Couldn't start aria2: \(error.localizedDescription)"
            note("downloader aria2 launch failed binary=\(binary) error=\(error.localizedDescription)")
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard let proc = process else { return }
        process = nil
        call("aria2.saveSession", []) { _ in }
        let pid = proc.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            proc.terminate()
            note("downloader aria2 stopped pid=\(pid)")
        }
        setAwake(false)
    }

    func ensureRunning() {
        if process == nil { start() }
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let curl = text.hasPrefix("curl ") ? CurlCommand.parse(text) : nil
        if text.hasPrefix("curl "), curl == nil {
            problem = "Couldn't find a link in that cURL command."
            note("downloader add rejected reason=curl-without-url length=\(text.count)")
            return false
        }
        let link = curl?.url ?? text
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https", "ftp", "sftp", "magnet"].contains(scheme) else {
            problem = "That doesn't look like a download link."
            note("downloader add rejected reason=not-a-url length=\(text.count)")
            return false
        }
        ensureRunning()
        var options: [String: Any] = [:]
        if let adopted = adoptPartial(for: url) {
            options["out"] = adopted
        } else if let name = fileName(of: url) {
            options["out"] = name
        }
        if let curl {
            if !curl.headers.isEmpty { options["header"] = curl.headers }
            if let agent = curl.userAgent { options["user-agent"] = agent }
            if let referer = curl.referer { options["referer"] = referer }
            let cookies = curl.headers.contains { $0.lowercased().hasPrefix("cookie:") }
            note("downloader add from curl host=\(url.host ?? scheme) headers=\(curl.headers.count) cookies=\(cookies) agent=\(curl.userAgent != nil) referer=\(curl.referer != nil)")
        }
        submit(link, options: options, host: url.host ?? scheme, attempt: 1)
        return true
    }

    private func fileName(of url: URL) -> String? {
        guard url.scheme?.lowercased() != "magnet" else { return nil }
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        guard name.contains("."), !name.hasPrefix("."), !name.contains("/") else { return nil }
        return name
    }

    private func submit(_ link: String, options: [String: Any], host: String, attempt: Int) {
        call("aria2.addUri", [[link], options]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                self.problem = nil
                note("downloader added gid=\(value as? String ?? "?") host=\(host) out=\(options["out"] as? String ?? "auto") attempt=\(attempt)")
                self.poll()
            case .failure(let error):
                if attempt < 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.submit(link, options: options, host: host, attempt: attempt + 1) }
                } else {
                    self.problem = "aria2 refused the link: \(error.localizedDescription)"
                    note("downloader add failed host=\(host) attempts=\(attempt) error=\(error.localizedDescription)")
                }
            }
        }
    }

    private func adoptPartial(for url: URL) -> String? {
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }
        let partial = Self.downloads.appendingPathComponent(name + ".crdownload")
        let target = Self.downloads.appendingPathComponent(name)
        let fm = FileManager.default
        guard fm.fileExists(atPath: partial.path), !fm.fileExists(atPath: target.path) else { return nil }
        do {
            try fm.copyItem(at: partial, to: target)
            let size = (try? fm.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? 0
            note("downloader adopted browser partial name=\(name) bytes=\(size)")
            return name
        } catch {
            note("downloader adopt failed name=\(name) error=\(error.localizedDescription)")
            return nil
        }
    }

    func pause(_ item: DownloadItem) { act("aria2.pause", item) }
    func resume(_ item: DownloadItem) { act("aria2.unpause", item) }

    func remove(_ item: DownloadItem) {
        if item.finished {
            act("aria2.removeDownloadResult", item)
        } else {
            act("aria2.remove", item)
        }
    }

    func clearFinished() {
        call("aria2.purgeDownloadResult", []) { [weak self] result in
            if case .failure(let error) = result { note("downloader clear failed error=\(error.localizedDescription)") }
            self?.poll()
        }
    }

    func reveal(_ item: DownloadItem) {
        guard let path = item.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func act(_ method: String, _ item: DownloadItem) {
        call(method, [item.id]) { [weak self] result in
            switch result {
            case .success: note("downloader \(method.replacingOccurrences(of: "aria2.", with: "")) gid=\(item.id) name=\(item.name)")
            case .failure(let error): note("downloader \(method) failed gid=\(item.id) error=\(error.localizedDescription)")
            }
            self?.poll()
        }
    }

    private func poll() {
        guard process != nil else { return }
        let keys = ["gid", "status", "totalLength", "completedLength", "downloadSpeed", "errorMessage", "files"]
        let batch: [[String: Any]] = [
            ["methodName": "aria2.tellActive", "params": ["token:\(secret)", keys]],
            ["methodName": "aria2.tellWaiting", "params": ["token:\(secret)", 0, 50, keys]],
            ["methodName": "aria2.tellStopped", "params": ["token:\(secret)", 0, 50, keys]],
        ]
        rpc("system.multicall", [batch], authed: false) { [weak self] result in
            guard let self, case .success(let value) = result, let groups = value as? [Any] else { return }
            let rows = groups.compactMap { ($0 as? [Any])?.first as? [[String: Any]] }.flatMap { $0 }
            self.apply(rows.map(Self.item))
        }
    }

    private static func item(_ row: [String: Any]) -> DownloadItem {
        let files = row["files"] as? [[String: Any]] ?? []
        let path = (files.first?["path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let uri = ((files.first?["uris"] as? [[String: Any]])?.first?["uri"] as? String).flatMap(URL.init(string:))
        let name = path.map { ($0 as NSString).lastPathComponent } ?? uri?.lastPathComponent ?? "Starting…"
        func number(_ key: String) -> Int64 { Int64(row[key] as? String ?? "") ?? 0 }
        return DownloadItem(id: row["gid"] as? String ?? UUID().uuidString, name: name, status: row["status"] as? String ?? "waiting",
                            total: number("totalLength"), done: number("completedLength"), speed: number("downloadSpeed"),
                            error: row["errorMessage"] as? String, path: path)
    }

    private func apply(_ fresh: [DownloadItem]) {
        for item in fresh {
            let before = known[item.id]
            if before != item.status {
                if before != nil || item.finished {
                    note("downloader status gid=\(item.id) name=\(item.name) from=\(before ?? "new") to=\(item.status) bytes=\(item.done)/\(item.total) error=\(item.error ?? "-")")
                }
                if before != nil, item.status == "complete" { notify(title: "Downloaded", body: item.name) }
                if before != nil, item.status == "error" { notify(title: "Download failed", body: "\(item.name): \(item.error ?? "unknown error")") }
                known[item.id] = item.status
            }
        }
        guard fresh != items else { return }
        items = fresh
        publish()
    }

    private func publish() {
        setAwake(items.contains { $0.status == "active" })
        onChange?()
    }

    private func setAwake(_ on: Bool) {
        if on, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "downloading files")
            note("downloader keeping mac awake")
        } else if !on, let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
            note("downloader released sleep hold")
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["app": "downloader"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { note("downloader notification failed title=\(title) error=\(error.localizedDescription)") }
        }
    }

    private func call(_ method: String, _ params: [Any], done: @escaping (Result<Any, Error>) -> Void) {
        rpc(method, params, authed: true, done: done)
    }

    private func rpc(_ method: String, _ params: [Any], authed: Bool, done: @escaping (Result<Any, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": "pocket", "method": method, "params": authed ? ["token:\(secret)"] + params : params]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: request) { data, _, error in
            let result: Result<Any, Error>
            if let error {
                result = .failure(error)
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let failure = json["error"] as? [String: Any] {
                    result = .failure(NSError(domain: "aria2", code: failure["code"] as? Int ?? 0,
                                              userInfo: [NSLocalizedDescriptionKey: failure["message"] as? String ?? "error"]))
                } else {
                    result = .success(json["result"] ?? NSNull())
                }
            } else {
                result = .failure(NSError(domain: "aria2", code: -1, userInfo: [NSLocalizedDescriptionKey: "unreadable reply"]))
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }
}
