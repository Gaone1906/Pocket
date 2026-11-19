import AppKit
import Foundation

enum PocketData {
    static let root: URL = {
        if let custom = ProcessInfo.processInfo.environment["POCKET_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Pocket", isDirectory: true)
    }()

    static var board: URL { root.appendingPathComponent("Pomodoro/board.json") }
    static var todos: URL { root.appendingPathComponent("todos.json") }
    static var schedule: URL { root.appendingPathComponent("schedule.json") }
    static var backups: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    static var repo: URL { root.appendingPathComponent("DataRepo", isDirectory: true) }
    static var syncState: URL { root.appendingPathComponent("sync-state.json") }
}

private struct VaultFile {
    let name: String
    let source: URL
    let noun: String

    static var all: [VaultFile] {
        [VaultFile(name: "board", source: PocketData.board, noun: "session"),
         VaultFile(name: "todos", source: PocketData.todos, noun: "to-do"),
         VaultFile(name: "schedule", source: PocketData.schedule, noun: "check-off")]
    }

    static func noun(_ name: String) -> String { all.first { $0.name == name }?.noun ?? "item" }
}

struct VaultSnapshot: Identifiable {
    let url: URL
    let day: Date
    var id: String { url.path }
}

final class DataVault: ObservableObject {
    static let shared = DataVault()
    static let keepDays = 30
    static let folderKey = "pocket.backup.folder"
    static let repoKey = "pocket.backup.repo"
    static let userKey = "pocket.backup.githubUser"

    @Published private(set) var lastSnapshot: Date?
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncProblem: String?
    @Published private(set) var incoming: [String: Int] = [:]

    private let queue = DispatchQueue(label: "pocket.vault", qos: .utility)
    private var syncPending = false
    private var mergers: [String: (Data) -> Void] = [:]
    private var overridden = Set<String>()
    private var held: [String: Int] = [:]
    private let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    private init() {
        lastSnapshot = (try? FileManager.default.contentsOfDirectory(at: PocketData.backups.appendingPathComponent("board"), includingPropertiesForKeys: [.contentModificationDateKey]))?
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    var repoURL: String? { UserDefaults.standard.string(forKey: Self.repoKey).flatMap { $0.isEmpty ? nil : $0 } }

    var mirrorFolder: URL? {
        if let custom = UserDefaults.standard.string(forKey: Self.folderKey), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        let cloud = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let drive = (try? FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent.hasPrefix("GoogleDrive-") }
        return drive?.appendingPathComponent("My Drive/Pocket Backups", isDirectory: true)
    }

    func start() {
        note("pocket vault started root=\(PocketData.root.path) mirror=\(mirrorFolder?.path ?? "none") repo=\(repoURL ?? "none")")
        for file in VaultFile.all {
            guard let data = try? Data(contentsOf: file.source), (try? JSONSerialization.jsonObject(with: data)) != nil else { continue }
            snapshot(data, name: file.name, count: -1)
        }
        scheduleSync(after: 20)
    }

    func snapshot(_ data: Data, name: String, count: Int) {
        queue.async { [self] in
            let folder = PocketData.backups.appendingPathComponent(name, isDirectory: true)
            let file = folder.appendingPathComponent("\(name)-\(dayFormat.string(from: Date())).json")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                note("pocket vault snapshot failed name=\(name) count=\(count) path=\(file.path) error=\(error.localizedDescription)")
                return
            }
            prune(folder, name: name)
            mirror(file, name: name)
            DispatchQueue.main.async { self.lastSnapshot = Date() }
        }
        scheduleSync(after: 90)
        CloudSync.shared.schedule(after: 4)
    }

    func snapshots(_ name: String) -> [VaultSnapshot] {
        let folder = PocketData.backups.appendingPathComponent(name, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            guard let day = day(of: url, name: name) else { return nil }
            return VaultSnapshot(url: url, day: day)
        }
        .sorted { $0.day > $1.day }
    }

    func recover<T>(_ name: String, decode: (Data) throws -> T) -> (T, VaultSnapshot)? {
        for snap in snapshots(name) {
            do {
                return (try decode(Data(contentsOf: snap.url)), snap)
            } catch {
                note("pocket vault snapshot unreadable name=\(name) path=\(snap.url.path) error=\(error.localizedDescription)")
            }
        }
        return nil
    }

    @discardableResult
    func quarantine(_ file: URL, name: String) -> URL? {
        let target = file.deletingLastPathComponent().appendingPathComponent("\(name).broken-\(stampFormat.string(from: Date())).json")
        do {
            try FileManager.default.moveItem(at: file, to: target)
            note("pocket vault quarantined name=\(name) from=\(file.path) to=\(target.path)")
            return target
        } catch {
            note("pocket vault quarantine failed name=\(name) path=\(file.path) error=\(error.localizedDescription)")
            return nil
        }
    }

    func keepAside(_ data: Data, name: String, reason: String) {
        let folder = PocketData.backups.appendingPathComponent(name, isDirectory: true)
        let file = folder.appendingPathComponent("\(name)-\(reason)-\(stampFormat.string(from: Date())).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            note("pocket vault kept aside name=\(name) reason=\(reason) path=\(file.path)")
        } catch {
            note("pocket vault keep aside failed name=\(name) reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private func day(of url: URL, name: String) -> Date? {
        let base = url.deletingPathExtension().lastPathComponent
        guard base.hasPrefix("\(name)-") else { return nil }
        return dayFormat.date(from: String(base.dropFirst(name.count + 1)))
    }

    private func prune(_ folder: URL, name: String) {
        let all = snapshots(name)
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: Date()) ?? .distantPast
        var monthsKept = Set<String>()
        var removed = 0
        for snap in all.sorted(by: { $0.day < $1.day }) {
            let month = String(dayFormat.string(from: snap.day).prefix(7))
            let firstOfMonth = monthsKept.insert(month).inserted
            guard snap.day < cutoff, !firstOfMonth else { continue }
            do {
                try FileManager.default.removeItem(at: snap.url)
                removed += 1
            } catch {
                note("pocket vault prune failed name=\(name) path=\(snap.url.path) error=\(error.localizedDescription)")
            }
        }
        if removed > 0 { note("pocket vault pruned name=\(name) removed=\(removed) kept=\(all.count - removed)") }
    }

    private func mirror(_ file: URL, name: String) {
        guard let root = mirrorFolder else { return }
        let folder = root.appendingPathComponent(name, isDirectory: true)
        let target = folder.appendingPathComponent(file.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: file, to: target)
        } catch {
            note("pocket vault mirror failed name=\(name) target=\(target.path) error=\(error.localizedDescription)")
        }
    }

    private func scheduleSync(after delay: TimeInterval) {
        guard repoURL != nil else { return }
        queue.async { [self] in
            guard !syncPending else { return }
            syncPending = true
            queue.asyncAfter(deadline: .now() + delay) { [self] in
                syncPending = false
                sync()
            }
        }
    }

    func register(_ name: String, merge: @escaping (Data) -> Void) {
        mergers[name] = merge
    }

    func bringIn() {
        queue.async { [self] in
            let waiting = incomingNames()
            let payloads = waiting.compactMap { name in
                (try? Data(contentsOf: PocketData.repo.appendingPathComponent("\(name).json"))).map { (name, $0) }
            }
            DispatchQueue.main.async { [self] in
                for (name, data) in payloads {
                    guard let merge = mergers[name] else {
                        note("pocket vault bring in skipped name=\(name) reason=no-store")
                        continue
                    }
                    merge(data)
                    note("pocket vault brought in name=\(name) bytes=\(data.count)")
                }
                syncNow()
            }
        }
    }

    func keepThisMac() {
        queue.async { [self] in
            let waiting = incomingNames()
            overridden.formUnion(waiting)
            note("pocket vault keeping local over github names=\(waiting.sorted().joined(separator: ","))")
            sync()
        }
    }

    private func incomingNames() -> [String] {
        Array(held.keys)
    }

    func syncNow() {
        queue.async { [self] in sync() }
    }

    private func sync() {
        guard let remote = repoURL else { return }
        let repo = PocketData.repo
        let files = FileManager.default
        if !files.fileExists(atPath: repo.appendingPathComponent(".git").path) {
            guard git(["clone", remote, repo.path], in: PocketData.root, step: "clone") else { return }
        }
        guard git(["pull", "--rebase", "--quiet"], in: repo, step: "pull") else { return }
        var sessions = 0
        var known = loadSyncState()
        var blocked: [String: Int] = [:]
        var pushed: [String: Set<String>] = [:]
        for file in VaultFile.all {
            let source = file.source
            let key = file.name
            let name = "\(key).json"
            let target = repo.appendingPathComponent(name)
            let local = Self.ids(in: try? Data(contentsOf: source), name: key)
            let remote = Self.ids(in: try? Data(contentsOf: target), name: key)
            let unseen = remote.subtracting(local).subtracting(known[key] ?? [])
            if !unseen.isEmpty, !overridden.contains(key) {
                blocked[key] = unseen.count
                note("pocket vault sync held name=\(key) unseen=\(unseen.count) local=\(local.count) remote=\(remote.count)")
                continue
            }
            guard files.fileExists(atPath: source.path) else { continue }
            pushed[key] = local
            do {
                if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
                try files.copyItem(at: source, to: target)
            } catch {
                finish(problem: "copy \(name) failed: \(error.localizedDescription)")
                return
            }
            if key == "board", let data = try? Data(contentsOf: source),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                sessions = (json["sessions"] as? [Any])?.count ?? 0
            }
        }
        let heldNote = blocked.isEmpty ? nil : Self.heldMessage(blocked)
        held = blocked
        DispatchQueue.main.async { self.incoming = blocked }
        guard git(["add", "-A"], in: repo, step: "add") else { return }
        if git(["diff", "--cached", "--quiet"], in: repo, step: "diff", quiet: true) {
            remember(pushed, into: &known)
            finish(problem: heldNote)
            note("pocket vault sync unchanged repo=\(remote) held=\(blocked.count)")
            return
        }
        let message = "backup \(stampFormat.string(from: Date())) sessions=\(sessions)"
        guard git(["commit", "--quiet", "-m", message], in: repo, step: "commit"),
              git(["push", "--quiet"], in: repo, step: "push") else { return }
        remember(pushed, into: &known)
        finish(problem: heldNote)
        note("pocket vault synced repo=\(remote) sessions=\(sessions) held=\(blocked.count)")
    }

    private static func heldMessage(_ blocked: [String: Int]) -> String {
        let parts = blocked.sorted { $0.key < $1.key }.map { "\($0.value) \(VaultFile.noun($0.key))\($0.value == 1 ? "" : "s")" }
        return "GitHub has \(parts.joined(separator: " and ")) this Mac doesn't"
    }

    private func remember(_ pushed: [String: Set<String>], into known: inout [String: Set<String>]) {
        guard !pushed.isEmpty else { return }
        for (key, ids) in pushed {
            known[key] = ids
            overridden.remove(key)
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: known.mapValues { $0.sorted() }, options: [.sortedKeys])
            try data.write(to: PocketData.syncState, options: .atomic)
        } catch {
            note("pocket vault sync state write failed path=\(PocketData.syncState.path) error=\(error.localizedDescription)")
        }
    }

    private func loadSyncState() -> [String: Set<String>] {
        guard let data = try? Data(contentsOf: PocketData.syncState),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return [:] }
        return json.mapValues(Set.init)
    }

    static func ids(in data: Data?, name: String) -> Set<String> {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let object = json as? [String: Any]
        let list: [Any]
        switch name {
        case "board": list = object?["sessions"] as? [Any] ?? []
        case "schedule": list = (object?["checks"] as? [Any] ?? []) + (object?["routines"] as? [Any] ?? [])
        default: list = json as? [Any] ?? []
        }
        return Set(list.compactMap { ($0 as? [String: Any])?["id"] as? String })
    }

    private func finish(problem: String?) {
        DispatchQueue.main.async {
            self.syncProblem = problem
            if problem == nil { self.lastSync = Date() }
        }
    }

    @discardableResult
    private func git(_ args: [String], in folder: URL, step: String, quiet: Bool = false) -> Bool {
        let user = UserDefaults.standard.string(forKey: Self.userKey) ?? ""
        let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "gh"
        let helper = "!f(){ echo username=\(user); echo password=$(\(gh) auth token\(user.isEmpty ? "" : " -u \(user)")); }; f"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "credential.helper=", "-c", "credential.helper=\(helper)"] + args
        process.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            finish(problem: "git \(step) could not run")
            note("pocket vault git failed step=\(step) error=\(error.localizedDescription)")
            return false
        }
        guard process.terminationStatus == 0 else {
            if !quiet {
                let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                finish(problem: "git \(step) failed")
                note("pocket vault git failed step=\(step) status=\(process.terminationStatus) detail=\(detail.prefix(300))")
            }
            return false
        }
        return true
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([PocketData.backups])
    }
}
