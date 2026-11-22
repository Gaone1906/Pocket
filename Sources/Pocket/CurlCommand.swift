import Foundation

struct CurlCommand {
    var url: String
    var headers: [String] = []
    var userAgent: String?
    var referer: String?

    private static let skippedHeaders: Set<String> = ["range", "accept-encoding", "content-length", "host"]
    private static let valueFlags: Set<String> = ["-X", "--request", "-d", "--data", "--data-raw", "--data-binary", "-u", "--user", "-o", "--output"]

    static func parse(_ text: String) -> CurlCommand? {
        let tokens = tokenize(text.replacingOccurrences(of: #"\\\s+"#, with: " ", options: .regularExpression))
        guard tokens.first == "curl" else { return nil }
        var url: String?
        var command = CurlCommand(url: "")
        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            switch token {
            case "-H", "--header":
                if let header = next {
                    let name = header.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
                    if name == "user-agent" {
                        command.userAgent = header.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
                    } else if name == "referer" {
                        command.referer = header.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
                    } else if !skippedHeaders.contains(name) {
                        command.headers.append(header)
                    }
                }
                index += 2
            case "-b", "--cookie":
                if let cookie = next { command.headers.append("Cookie: \(cookie)") }
                index += 2
            case "-A", "--user-agent":
                command.userAgent = next
                index += 2
            case "-e", "--referer":
                command.referer = next
                index += 2
            case "--url":
                url = url ?? next
                index += 2
            default:
                if valueFlags.contains(token) {
                    index += 2
                } else {
                    if !token.hasPrefix("-") { url = url ?? token }
                    index += 1
                }
            }
        }
        guard let url else { return nil }
        command.url = url
        return command
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var chars = Array(text)[...]
        while let char = chars.popFirst() {
            switch char {
            case " ", "\t", "\n", "\r":
                if inToken { tokens.append(current); current = ""; inToken = false }
            case "'":
                inToken = true
                while let c = chars.popFirst(), c != "'" { current.append(c) }
            case "$" where chars.first == "'":
                inToken = true
                chars.removeFirst()
                while let c = chars.popFirst(), c != "'" {
                    if c == "\\", let escaped = chars.popFirst() {
                        switch escaped {
                        case "n": current.append("\n")
                        case "t": current.append("\t")
                        case "r": current.append("\r")
                        default: current.append(escaped)
                        }
                    } else {
                        current.append(c)
                    }
                }
            case "\"":
                inToken = true
                while let c = chars.popFirst(), c != "\"" {
                    if c == "\\", let escaped = chars.popFirst() { current.append(escaped) } else { current.append(c) }
                }
            case "\\":
                inToken = true
                if let escaped = chars.popFirst() { current.append(escaped) }
            default:
                inToken = true
                current.append(char)
            }
        }
        if inToken { tokens.append(current) }
        return tokens
    }
}
