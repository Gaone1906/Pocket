import AppKit

final class MatineeApp: WebApp {
    static let pathKey = "pocket.matinee.path"
    static let defaultPath = "~/Files/Personal Projects/Matinee"
    static let healthURL = URL(string: "http://127.0.0.1:47811/health")!
    static let shutdownURL = URL(string: "http://127.0.0.1:47811/shutdown")!
    static let logFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Matinee")

    var engine: Process?
    var superviseTimer: Timer?
    var engineUp: Bool?
    var engineVersion = "-"
    var spawnedByUs = false
    var failures = 0
    var spawnedAt = Date.distantPast
    var nextSpawnAllowed = Date.distantPast
    var warmupTicks = 0
    var problem: String?
    var stopping = false

    var repoURL: URL {
        let raw = UserDefaults.standard.string(forKey: MatineeApp.pathKey) ?? MatineeApp.defaultPath
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    override func start() {
        super.start()
        stopping = false
        note("pocket matinee supervising path=\(repoURL.path)")
        supervise(reason: "start")
        superviseTimer?.invalidate()
        superviseTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.supervise(reason: "interval") }
        superviseTimer?.tolerance = 5
    }

    override func load(reason: String) {
        let fresh = web == nil
        super.load(reason: reason)
        if fresh, engineUp != true { showPlaceholder() }
    }

    func supervise(reason: String) {
        probe { [weak self] up, version in
            guard let self, !self.stopping else { return }
            self.record(up: up, version: version, reason: reason)
            guard !up else { return }
            self.respawnIfDue(reason: reason)
        }
    }

    func probe(_ done: @escaping (Bool, String) -> Void) {
        var request = URLRequest(url: MatineeApp.healthURL)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, response, error in
            var up = false
            var version = "-"
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
               let json = data.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any], json["ok"] as? Bool == true {
                up = true
                version = json["version"] as? String ?? "-"
            }
            DispatchQueue.main.async { done(up, version) }
        }.resume()
    }

    func record(up: Bool, version: String, reason: String) {
        if engineUp != up {
            let pid = engine.map { "\($0.processIdentifier)" } ?? "-"
            note("pocket matinee engine \(up ? "answering" : "silent") reason=\(reason) version=\(version) ours=\(spawnedByUs) pid=\(pid)")
            let wasDown = engineUp == false || engineUp == nil
            engineUp = up
            engineVersion = version
            if up {
                failures = 0
                problem = nil
                if wasDown, web != nil {
                    note("pocket matinee reloading page after engine answered")
                    web?.load(URLRequest(url: site.url))
                }
            } else if web != nil {
                showPlaceholder()
            }
        }
    }

    func warmUp() {
        warmupTicks = 20
        func tick() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.stopping, self.warmupTicks > 0, self.engineUp != true else { return }
                self.warmupTicks -= 1
                self.probe { up, version in
                    self.record(up: up, version: version, reason: "warmup")
                    if !up { tick() }
                }
            }
        }
        tick()
    }

    func respawnIfDue(reason: String) {
        if let engine, engine.isRunning, Date().timeIntervalSince(spawnedAt) < 45 { return }
        if engine?.isRunning == true {
            note("pocket matinee engine running but silent pid=\(engine!.processIdentifier) for=\(Int(Date().timeIntervalSince(spawnedAt)))s; terminating")
            engine?.terminate()
            return
        }
        guard Date() >= nextSpawnAllowed else {
            return note("pocket matinee respawn backing off wait=\(Int(nextSpawnAllowed.timeIntervalSinceNow))s failures=\(failures)")
        }
        spawn(reason: reason)
    }

    func findNode() -> String? {
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v node"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        do { try shell.run() } catch {
            note("pocket matinee node lookup failed cause=\(error.localizedDescription)")
            return nil
        }
        shell.waitUntilExit()
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return !found.isEmpty && FileManager.default.isExecutableFile(atPath: found) ? found : nil
    }

    func spawn(reason: String) {
        let script = repoURL.appendingPathComponent("engine/server.js")
        guard FileManager.default.fileExists(atPath: script.path) else {
            return fail("Matinee was not found at \(repoURL.path). Set the folder with: defaults write com.pranav.pocket \(MatineeApp.pathKey) \"/path/to/Matinee\"",
                        log: "pocket matinee spawn blocked cause=engine script missing path=\(script.path)")
        }
        guard let node = findNode() else {
            return fail("Node.js was not found. Install it (brew install node), then choose Restart engine.",
                        log: "pocket matinee spawn blocked cause=node missing")
        }
        try? FileManager.default.createDirectory(at: MatineeApp.logFolder, withIntermediateDirectories: true)
        let logPath = MatineeApp.logFolder.appendingPathComponent("engine-stdout.log")
        if !FileManager.default.fileExists(atPath: logPath.path) { FileManager.default.createFile(atPath: logPath.path, contents: nil) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [script.path]
        process.currentDirectoryURL = repoURL
        if let handle = try? FileHandle(forWritingTo: logPath) {
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
        }
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                let expected = self.stopping || self.engine !== finished
                note("pocket matinee engine exited pid=\(finished.processIdentifier) status=\(finished.terminationStatus) reason=\(finished.terminationReason == .exit ? "exit" : "signal") expected=\(expected)")
                if self.engine === finished {
                    self.engine = nil
                    if !self.stopping {
                        self.spawnedByUs = false
                        self.probe { up, version in self.record(up: up, version: version, reason: "exit") }
                    }
                }
            }
        }
        do {
            try process.run()
        } catch {
            return fail("Matinee's engine could not start: \(error.localizedDescription)",
                        log: "pocket matinee spawn failed node=\(node) path=\(script.path) cause=\(error.localizedDescription)")
        }
        engine = process
        spawnedByUs = true
        spawnedAt = Date()
        failures += 1
        nextSpawnAllowed = Date().addingTimeInterval(min(600, 30 * pow(2, Double(failures - 1))))
        note("pocket matinee spawned pid=\(process.processIdentifier) reason=\(reason) node=\(node) script=\(script.path) attempt=\(failures) log=\(logPath.path)")
        warmUp()
    }

    func fail(_ message: String, log: String) {
        note(log)
        problem = message
        failures += 1
        nextSpawnAllowed = Date().addingTimeInterval(min(600, 30 * pow(2, Double(failures - 1))))
        if web != nil { showPlaceholder() }
    }

    func showPlaceholder() {
        let text = problem ?? "Starting the Matinee engine"
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <html><head><meta name="color-scheme" content="light dark"><title>Matinee</title></head>
        <body style="font: 14px -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; text-align: center; padding: 0 28px; box-sizing: border-box">
        <div><div style="font-size: 17px; font-weight: 600; margin-bottom: 8px">Matinee</div><div style="opacity: .7; line-height: 1.45">\(escaped)</div></div>
        </body></html>
        """
        web?.loadHTMLString(html, baseURL: nil)
        note("pocket matinee placeholder shown problem=\(problem != nil) text=\(text)")
    }

    func requestShutdown(wait: TimeInterval) -> Bool {
        var request = URLRequest(url: MatineeApp.shutdownURL)
        request.httpMethod = "POST"
        request.timeoutInterval = wait
        let gate = DispatchSemaphore(value: 0)
        var status = -1
        var cause = "-"
        URLSession.shared.dataTask(with: request) { _, response, error in
            status = (response as? HTTPURLResponse)?.statusCode ?? -1
            cause = error?.localizedDescription ?? "-"
            gate.signal()
        }.resume()
        _ = gate.wait(timeout: .now() + wait + 0.5)
        note("pocket matinee shutdown requested status=\(status) cause=\(cause)")
        return status == 202 || status == 200
    }

    override func stop() {
        stopping = true
        superviseTimer?.invalidate()
        superviseTimer = nil
        if spawnedByUs {
            _ = requestShutdown(wait: 2)
            if let engine {
                let deadline = Date().addingTimeInterval(6)
                while engine.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
                if engine.isRunning {
                    note("pocket matinee engine still running after grace; terminating pid=\(engine.processIdentifier)")
                    engine.terminate()
                } else {
                    note("pocket matinee engine stopped pid=\(engine.processIdentifier) status=\(engine.terminationStatus)")
                }
            }
        } else {
            note("pocket matinee leaving engine running ours=false")
        }
        engine = nil
        spawnedByUs = false
        engineUp = nil
        super.stop()
    }

    @objc func restartEngine() {
        note("pocket matinee restart requested source=menu ours=\(spawnedByUs)")
        failures = 0
        problem = nil
        nextSpawnAllowed = .distantPast
        DispatchQueue.global().async { [weak self] in
            let accepted = self?.requestShutdown(wait: 2) ?? false
            DispatchQueue.main.asyncAfter(deadline: .now() + (accepted ? 2 : 0)) {
                guard let self, !self.stopping else { return }
                if self.engine?.isRunning == true { self.engine?.terminate() }
                self.engineUp = nil
                self.supervise(reason: "restart")
            }
        }
    }

    @objc func openLogs() {
        try? FileManager.default.createDirectory(at: MatineeApp.logFolder, withIntermediateDirectories: true)
        let opened = NSWorkspace.shared.open(MatineeApp.logFolder)
        note("pocket matinee logs opened ok=\(opened) path=\(MatineeApp.logFolder.path)")
    }

    override func menuItems() -> [NSMenuItem] {
        [NSMenuItem(title: "Reload Matinee", action: #selector(reload), keyEquivalent: ""),
         NSMenuItem(title: "Restart engine", action: #selector(restartEngine), keyEquivalent: ""),
         NSMenuItem(title: "Open Matinee logs", action: #selector(openLogs), keyEquivalent: "")]
            .map { $0.target = self; return $0 }
    }
}
