import AppKit
import Foundation

struct UpdateFailure: Error {
    let message: String
    let detail: String
}

final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle
        case working(String)
        case upToDate
        case failed(String, String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastLine = ""

    let source = Bundle.main.object(forInfoDictionaryKey: "PocketSource") as? String
    let installed = Bundle.main.object(forInfoDictionaryKey: "PocketCommit") as? String
    private let logPath = NSHomeDirectory() + "/Library/Logs/pocket-update.log"
    private let queue = DispatchQueue(label: "pocket.updater")

    var running: Bool {
        if case .working = phase { return true }
        return false
    }

    func start() {
        guard !running else { return }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        note("pocket update started id=\(id) source=\(source ?? "none") installed=\(installed ?? "none")")
        set(.working("Checking your checkout…"))
        queue.async { [self] in
            do {
                try update(id: id)
            } catch let failure as UpdateFailure {
                note("pocket update failed id=\(id) reason=\(failure.message) detail=\(failure.detail.suffix(400).replacingOccurrences(of: "\n", with: " | "))")
                set(.failed(failure.message, failure.detail))
            } catch {
                note("pocket update failed id=\(id) error=\(error.localizedDescription)")
                set(.failed("Update failed.", error.localizedDescription))
            }
        }
    }

    private func update(id: String) throws {
        guard let source, FileManager.default.fileExists(atPath: source + "/Package.swift") else {
            throw UpdateFailure(message: "Pocket doesn't know where its source is.",
                                detail: "Run scripts/install.sh once from your Pocket checkout; later updates can use this button.")
        }
        let branch = try git(["rev-parse", "--abbrev-ref", "HEAD"], in: source, step: "read the branch")
        guard branch == "main" else {
            throw UpdateFailure(message: "Your checkout is on \(branch), not main.",
                                detail: "Switch \(source) to main to update. Nothing was changed.")
        }
        let dirty = try git(["status", "--porcelain", "--untracked-files=no"], in: source, step: "check for local changes")
        guard dirty.isEmpty else {
            let files = dirty.split(separator: "\n").prefix(6).joined(separator: "\n")
            throw UpdateFailure(message: "You have uncommitted changes, so nothing was pulled.",
                                detail: "Commit or stash them in \(source) first:\n\(files)")
        }
        set(.working("Fetching main from GitHub…"))
        _ = try git(["fetch", "origin", "main"], in: source, step: "fetch from GitHub")
        let ahead = Int(try git(["rev-list", "--count", "origin/main..HEAD"], in: source, step: "compare with GitHub")) ?? 0
        let behind = Int(try git(["rev-list", "--count", "HEAD..origin/main"], in: source, step: "compare with GitHub")) ?? 0
        guard ahead == 0 else {
            throw UpdateFailure(message: "Your main has \(ahead) commit\(ahead == 1 ? "" : "s") that GitHub doesn't.",
                                detail: "Push or move them off main in \(source) first. Nothing was changed.")
        }
        if behind > 0 {
            set(.working("Pulling \(behind) new commit\(behind == 1 ? "" : "s")…"))
            _ = try git(["merge", "--ff-only", "origin/main"], in: source, step: "pull main")
        }
        let head = try git(["rev-parse", "--short", "HEAD"], in: source, step: "read the new commit")
        note("pocket update pulled id=\(id) behind=\(behind) head=\(head) installed=\(installed ?? "none")")
        if behind == 0, head == installed {
            note("pocket update unchanged id=\(id) head=\(head)")
            set(.upToDate)
            return
        }
        set(.working("Building \(head)…"))
        let build = run(["swift", "build", "-c", "release"], in: source)
        guard build.code == 0 else {
            throw UpdateFailure(message: "The build failed, so the running Pocket was kept.",
                                detail: tail(build.output, lines: 12))
        }
        note("pocket update built id=\(id) head=\(head)")
        set(.working("Installing \(head) and relaunching…"))
        try install(id: id, source: source)
    }

    private func install(id: String, source: String) throws {
        FileManager.default.createFile(atPath: logPath, contents: nil)
        guard let log = FileHandle(forWritingAtPath: logPath) else {
            throw UpdateFailure(message: "Couldn't open the update log.", detail: logPath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [source + "/scripts/install.sh"]
        process.currentDirectoryURL = URL(fileURLWithPath: source)
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] finished in
            guard let self, finished.terminationStatus != 0 else { return }
            let output = (try? String(contentsOfFile: self.logPath, encoding: .utf8)) ?? ""
            note("pocket update install failed id=\(id) status=\(finished.terminationStatus)")
            self.set(.failed("Installing failed, so the running Pocket was kept.", self.tail(output, lines: 12)))
        }
        try process.run()
        note("pocket update installing id=\(id) pid=\(process.processIdentifier) log=\(logPath)")
    }

    private func git(_ args: [String], in dir: String, step: String) throws -> String {
        let result = run(["git"] + args, in: dir)
        guard result.code == 0 else {
            throw UpdateFailure(message: "Couldn't \(step).", detail: tail(result.output, lines: 8))
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ args: [String], in dir: String) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var collected = Data()
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            collected.append(chunk)
            lock.unlock()
            if let line = String(decoding: chunk, as: UTF8.self).split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let text = String(line.prefix(140))
                DispatchQueue.main.async { self?.lastLine = text }
            }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return (-1, "\(args.first ?? "") couldn't start: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        collected.append(rest)
        let output = String(decoding: collected, as: UTF8.self)
        lock.unlock()
        return (process.terminationStatus, output)
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["GIT_TERMINAL_PROMPT"] = "0"
        return env
    }

    private func tail(_ text: String, lines: Int) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }

    private func set(_ phase: Phase) {
        DispatchQueue.main.async {
            self.phase = phase
            if case .working = phase {} else { self.lastLine = "" }
        }
    }
}
