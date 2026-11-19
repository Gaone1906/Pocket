import Foundation
import Network

final class PocketServer {
    static let shared = PocketServer()
    static let port: UInt16 = 8977

    private var listener: NWListener?

    private struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data
    }

    private struct Response {
        let status: Int
        let body: Any?
    }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: note("pocket server listening port=\(Self.port)")
                case .failed(let error): note("pocket server failed port=\(Self.port) error=\(error)")
                default: break
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            note("pocket server could not start port=\(Self.port) error=\(error.localizedDescription)")
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.reply(connection, request: request)
            } else if complete || error != nil || buffer.count > 262_144 {
                if let error { note("pocket server receive failed bytes=\(buffer.count) error=\(error)") }
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private static func parse(_ data: Data) -> Request? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "") ?? 0
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        let target = parts[1].split(separator: "?", maxSplits: 1)
        var query: [String: String] = [:]
        if target.count == 2 {
            for pair in target[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                if let key = kv.first { query[key] = kv.count == 2 ? kv[1] : "" }
            }
        }
        return Request(method: String(parts[0]), path: String(target.first ?? ""), query: query, headers: headers, body: Data(body.prefix(length)))
    }

    private func reply(_ connection: NWConnection, request: Request) {
        let origin = request.headers["origin"]
        let allowed = origin.map { URL(string: $0).map { ["localhost", "127.0.0.1"].contains($0.host ?? "") } ?? false } ?? true
        let response: Response
        if !allowed {
            note("pocket server refused origin=\(origin ?? "-") method=\(request.method) path=\(request.path)")
            response = Response(status: 403, body: ["error": "origin not allowed"])
        } else if request.method == "OPTIONS" {
            response = Response(status: 204, body: nil)
        } else {
            response = route(request)
        }
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\nConnection: close\r\nCache-Control: no-store\r\n"
        if allowed, let origin {
            head += "Access-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, X-Pocket-Source\r\nAccess-Control-Allow-Private-Network: true\r\nVary: Origin\r\n"
        }
        let body = response.body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        head += "Content-Length: \(body.count)\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { error in
            if let error { note("pocket server send failed path=\(request.path) status=\(response.status) error=\(error)") }
            connection.cancel()
        })
    }

    private struct Invalid: Error {
        let message: String
    }

    private static let routes = [
        "GET /": "this list",
        "GET /pomodoro": "timer state",
        "POST /pomodoro/start": "start or resume focus; body {project?, focus?, rest?, long?} in minutes, hold? to wait for a start after each break",
        "POST /pomodoro/pause": "pause a running phase",
        "POST /pomodoro/resume": "resume a paused phase",
        "POST /pomodoro/stop": "stop and reset to idle",
        "GET /pomodoro/projects": "board projects",
        "GET /pomodoro/sessions?since=<ISO 8601>&project=<name>": "finished focus sessions",
        "GET /pomodoro/stats": "today and all-time totals",
        "GET /cloud": "cloud sync status",
        "POST /cloud/signin": "email a sign-in code; body {email}",
        "POST /cloud/verify": "finish sign-in; body {code}",
        "POST /cloud/sync": "sync with the cloud now",
        "POST /cloud/signout": "stop syncing on this Mac",
    ]

    private func route(_ request: Request) -> Response {
        if request.method == "GET", request.path == "/" {
            return Response(status: 200, body: ["app": "pocket", "routes": Self.routes])
        }
        if request.path == "/cloud" || request.path.hasPrefix("/cloud/") {
            return cloud(request)
        }
        guard let pomodoro = AppDelegate.shared.app("pomodoro") as? PomodoroApp else {
            if request.method == "POST" { note("pocket server pomodoro unavailable path=\(request.path) cause=not enabled") }
            return Response(status: 409, body: ["error": "Pomodoro isn't enabled in Pocket"])
        }
        let source = request.headers["x-pocket-source"] ?? request.headers["origin"] ?? request.headers["user-agent"] ?? "local"
        let store = PomodoroBoardStore.shared
        do {
            switch (request.method, request.path) {
            case ("GET", "/pomodoro"):
                return Response(status: 200, body: pomodoro.remoteState())
            case ("POST", "/pomodoro/start"):
                let json = try Self.object(request.body)
                let project = try Self.text(json, "project")
                let plan = PomodoroPlan(
                    focus: try Self.minutes(json, "focus", 1...240),
                    rest: try Self.minutes(json, "rest", 1...90),
                    long: try Self.minutes(json, "long", 1...120)
                )
                pomodoro.remoteStart(project: project, plan: plan, hold: try Self.flag(json, "hold"), source: source)
                return Response(status: 200, body: pomodoro.remoteState())
            case ("POST", "/pomodoro/pause"):
                pomodoro.remotePause(source: source)
                return Response(status: 200, body: pomodoro.remoteState())
            case ("POST", "/pomodoro/resume"):
                pomodoro.remoteResume(source: source)
                return Response(status: 200, body: pomodoro.remoteState())
            case ("POST", "/pomodoro/stop"):
                pomodoro.remoteStop(source: source)
                return Response(status: 200, body: pomodoro.remoteState())
            case ("GET", "/pomodoro/projects"):
                return Response(status: 200, body: ["projects": store.projects.map { project in
                    let minutes = store.sessions(in: project.id).reduce(0) { $0 + $1.minutes }
                    return ["id": project.id.uuidString, "name": project.name, "minutes": minutes, "sessions": Self.units(minutes)] as [String: Any]
                }])
            case ("GET", "/pomodoro/sessions"):
                var sessions = store.sessions
                if let since = request.query["since"] {
                    guard let date = ISO8601DateFormatter().date(from: since) else { throw Invalid(message: "since must be ISO 8601, e.g. 2026-11-16T00:00:00Z") }
                    sessions = sessions.filter { $0.ended >= date }
                }
                if let name = request.query["project"] {
                    guard let project = store.projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw Invalid(message: "no project named \(name)") }
                    sessions = sessions.filter { $0.project == project.id }
                }
                let formatter = ISO8601DateFormatter()
                return Response(status: 200, body: ["sessions": sessions.sorted { $0.ended > $1.ended }.map { session in
                    ["id": session.id.uuidString, "ended": formatter.string(from: session.ended), "minutes": session.minutes, "project": store.project(session.project)?.name ?? NSNull()] as [String: Any]
                }])
            case ("GET", "/pomodoro/stats"):
                let today = store.sessions.filter { Calendar.current.isDateInToday($0.ended) }.reduce(0) { $0 + $1.minutes }
                let total = store.sessions.reduce(0) { $0 + $1.minutes }
                return Response(status: 200, body: [
                    "today": ["minutes": today, "sessions": Self.units(today)],
                    "allTime": ["minutes": total, "sessions": Self.units(total)],
                    "sessionMinutes": TallyStick.fullMinutes,
                ])
            default:
                return Response(status: 404, body: ["error": "no route \(request.method) \(request.path)", "routes": Self.routes])
            }
        } catch let invalid as Invalid {
            note("pocket server rejected source=\(source) method=\(request.method) path=\(request.path) cause=\(invalid.message)")
            return Response(status: 400, body: ["error": invalid.message])
        } catch {
            note("pocket server failed source=\(source) method=\(request.method) path=\(request.path) error=\(error)")
            return Response(status: 500, body: ["error": "\(error)"])
        }
    }

    private func cloud(_ request: Request) -> Response {
        let source = request.headers["x-pocket-source"] ?? request.headers["origin"] ?? request.headers["user-agent"] ?? "local"
        let cloud = CloudSync.shared
        do {
            switch (request.method, request.path) {
            case ("GET", "/cloud"):
                return Response(status: 200, body: cloud.status())
            case ("POST", "/cloud/signin"):
                guard let email = try Self.text(Self.object(request.body), "email"), email.contains("@") else { throw Invalid(message: "body needs {\"email\": \"you@example.com\"}") }
                try cloud.sendCode(email: email)
                note("pocket server cloud code requested source=\(source) email=\(email)")
                return Response(status: 200, body: ["sent": true, "email": email] as [String: Any])
            case ("POST", "/cloud/verify"):
                guard let code = try Self.text(Self.object(request.body), "code"), !code.isEmpty else { throw Invalid(message: "body needs {\"code\": \"123456\"}") }
                try cloud.verify(code: code)
                note("pocket server cloud verified source=\(source)")
                return Response(status: 200, body: cloud.status())
            case ("POST", "/cloud/sync"):
                cloud.syncNow()
                note("pocket server cloud sync requested source=\(source)")
                return Response(status: 202, body: cloud.status())
            case ("POST", "/cloud/signout"):
                cloud.signOut()
                note("pocket server cloud signout source=\(source)")
                return Response(status: 200, body: ["signedIn": false])
            default:
                return Response(status: 404, body: ["error": "no route \(request.method) \(request.path)", "routes": Self.routes])
            }
        } catch let invalid as Invalid {
            note("pocket server rejected source=\(source) method=\(request.method) path=\(request.path) cause=\(invalid.message)")
            return Response(status: 400, body: ["error": invalid.message])
        } catch {
            note("pocket server cloud failed source=\(source) path=\(request.path) error=\(error)")
            return Response(status: 502, body: ["error": "\(error)"])
        }
    }

    private static func units(_ minutes: Int) -> Double {
        (Double(minutes) / Double(TallyStick.fullMinutes) * 10).rounded() / 10
    }

    private static func object(_ body: Data) throws -> [String: Any] {
        guard !body.isEmpty else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw Invalid(message: "body must be a JSON object") }
        return json
    }

    private static func text(_ json: [String: Any], _ key: String) throws -> String? {
        guard let value = json[key], !(value is NSNull) else { return nil }
        guard let text = value as? String else { throw Invalid(message: "\(key) must be a string") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func flag(_ json: [String: Any], _ key: String) throws -> Bool? {
        guard let value = json[key], !(value is NSNull) else { return nil }
        guard let flag = value as? Bool else { throw Invalid(message: "\(key) must be true or false") }
        return flag
    }

    private static func minutes(_ json: [String: Any], _ key: String, _ range: ClosedRange<Int>) throws -> Int? {
        guard let value = json[key], !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == number.doubleValue.rounded(), range.contains(number.intValue) else {
            throw Invalid(message: "\(key) must be a whole number of minutes from \(range.lowerBound) to \(range.upperBound)")
        }
        return number.intValue
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 502: return "Bad Gateway"
        default: return "Error"
        }
    }
}
