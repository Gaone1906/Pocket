import Foundation
import Network

final class PocketServer {
    static let shared = PocketServer()
    static let port: UInt16 = 8977

    private var listener: NWListener?

    private struct Request {
        let method: String
        let path: String
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
        return Request(method: String(parts[0]), path: String(parts[1].split(separator: "?").first ?? ""), headers: headers, body: Data(body.prefix(length)))
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
            head += "Access-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\nVary: Origin\r\n"
        }
        let body = response.body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        head += "Content-Length: \(body.count)\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { error in
            if let error { note("pocket server send failed path=\(request.path) status=\(response.status) error=\(error)") }
            connection.cancel()
        })
    }

    private func route(_ request: Request) -> Response {
        guard let pomodoro = AppDelegate.shared.app("pomodoro") as? PomodoroApp else {
            if request.method == "POST" { note("pocket server pomodoro unavailable path=\(request.path) cause=not enabled") }
            return Response(status: 409, body: ["error": "Pomodoro isn't enabled in Pocket"])
        }
        let source = request.headers["origin"] ?? "local"
        switch (request.method, request.path) {
        case ("GET", "/pomodoro"):
            return Response(status: 200, body: pomodoro.remoteState())
        case ("POST", "/pomodoro/start"):
            let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let project = (json?["project"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            pomodoro.remoteStart(project: project?.isEmpty == false ? project : nil, source: source)
            return Response(status: 200, body: pomodoro.remoteState())
        case ("POST", "/pomodoro/stop"):
            pomodoro.remoteStop(source: source)
            return Response(status: 200, body: pomodoro.remoteState())
        default:
            return Response(status: 404, body: ["error": "no route \(request.method) \(request.path)"])
        }
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        default: return "Error"
        }
    }
}
