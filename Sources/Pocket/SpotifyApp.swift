import AppKit
import WebKit

final class SpotifyApp: WebApp {
    static let bundleID = "com.spotify.client"
    static let claimScript = """
    tell application id "com.spotify.client"
        if player state is playing then return "playing"
        set level to sound volume
        set sound volume to 0
        play
        delay 0.8
        pause
        set sound volume to level
        return "claimed"
    end tell
    """

    var watchers: [NSObjectProtocol] = []
    var launchedAt = Date.distantPast
    var launching = false
    var claimed = false
    var showingCompanion = false
    var presentWork: DispatchWorkItem?
    var holdUntil = Date.distantPast
    var claimPending = false

    var companion: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyApp.bundleID).first { !$0.isTerminated }
    }

    override func start() {
        super.start()
        watch()
        if let app = companion { keepHidden(app, reason: "pocket started") }
    }

    override func stop() {
        let center = NSWorkspace.shared.notificationCenter
        watchers.forEach(center.removeObserver)
        watchers = []
        super.stop()
    }

    override func shouldStayOpen() -> Bool {
        super.shouldStayOpen() || Date() < holdUntil
    }

    override func didShow() {
        super.didShow()
        ensureCompanion(reason: "opened")
    }

    func watch() {
        guard watchers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let spotify: (Notification) -> NSRunningApplication? = { event in
            let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            return app?.bundleIdentifier == SpotifyApp.bundleID ? app : nil
        }
        watchers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, let app = spotify(event) else { return }
            self.keepHidden(app, reason: "launched")
            self.claimWhenReady(attempt: 0)
        })
        watchers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, let app = spotify(event) else { return }
            self.companionActivated(app)
        })
        watchers.append(center.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, let app = spotify(event) else { return }
            self.keepHidden(app, reason: "unhidden")
        })
        watchers.append(center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, let app = spotify(event), self.showingCompanion else { return }
            self.showingCompanion = false
            self.keepHidden(app, reason: "left")
        })
        watchers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, let app = spotify(event), app.processIdentifier > 0, self.companion == nil else { return }
            self.claimed = false
            self.showingCompanion = false
            note("pocket spotify app quit app=\(self.spec.id)")
        })
    }

    func companionActivated(_ app: NSRunningApplication) {
        guard !showingCompanion else { return }
        let fresh = Date().timeIntervalSince(launchedAt) < 15
        keepHidden(app, reason: fresh ? "launch activated" : "activated")
        if fresh, !isShown { return }
        presentWork?.cancel()
        holdUntil = max(holdUntil, Date().addingTimeInterval(2))
        let work = DispatchWorkItem { [weak self] in self?.present() }
        presentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func present() {
        holdUntil = max(holdUntil, Date().addingTimeInterval(2))
        guard isShown else { return show(anchor: AppDelegate.shared.anchor(for: spec.id), source: "spotify app") }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        note("pocket spotify panel refocused app=\(spec.id) source=spotify app")
    }

    func keepHidden(_ app: NSRunningApplication, reason: String) {
        guard !showingCompanion, app.processIdentifier > 0, !app.isHidden || app.isActive else { return }
        app.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !app.isTerminated else { return }
            if !app.isHidden, !self.showingCompanion { app.hide() }
            note("pocket spotify app hidden app=\(self.spec.id) reason=\(reason) pid=\(app.processIdentifier) hidden=\(app.isHidden)")
        }
    }

    func ensureCompanion(reason: String) {
        if companion != nil {
            if !claimed { claimWhenReady(attempt: 0) }
            return
        }
        guard !launching else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyApp.bundleID) else {
            return note("pocket spotify app missing app=\(spec.id) reason=\(reason) fallback=web player")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        launching = true
        launchedAt = Date()
        if isShown { holdUntil = Date().addingTimeInterval(8) }
        note("pocket spotify app launching app=\(spec.id) reason=\(reason) path=\(url.path)")
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launching = false
                if let error { return note("pocket spotify app launch failed app=\(self.spec.id) cause=\(error.localizedDescription)") }
                note("pocket spotify app launched app=\(self.spec.id) pid=\(app?.processIdentifier ?? 0)")
                if let app { self.keepHidden(app, reason: "launched") }
                self.claimWhenReady(attempt: 0)
            }
        }
    }

    func claimWhenReady(attempt: Int) {
        guard !claimed, !claimPending, companion != nil else { return }
        claimPending = true
        let wait: TimeInterval = attempt == 0 ? 4 : 5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.claimPending = false
            self?.runClaim(attempt: attempt)
        }
    }

    func runClaim(attempt: Int) {
        guard !claimed, companion != nil else { return }
        let task = Process()
        let out = Pipe()
        let err = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", SpotifyApp.claimScript]
        task.standardOutput = out
        task.standardError = err
        task.terminationHandler = { [weak self] process in
            let result = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let problem = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                let ok = process.terminationStatus == 0
                note("pocket spotify claim app=\(self.spec.id) attempt=\(attempt) ok=\(ok) result=\(result.isEmpty ? "-" : result) error=\(problem.isEmpty ? "-" : problem)")
                if ok {
                    self.claimed = true
                    if let app = self.companion { self.keepHidden(app, reason: "claimed") }
                } else if attempt < 3 {
                    self.claimWhenReady(attempt: attempt + 1)
                }
            }
        }
        do {
            try task.run()
        } catch {
            note("pocket spotify claim failed app=\(spec.id) attempt=\(attempt) cause=\(error.localizedDescription)")
        }
    }

    override func menuItems() -> [NSMenuItem] {
        super.menuItems() + [
            NSMenuItem(title: "Show the Spotify app", action: #selector(showCompanion), keyEquivalent: ""),
            NSMenuItem(title: "Play on this Mac's Spotify app", action: #selector(reclaim), keyEquivalent: "")
        ].map { $0.target = self; return $0 }
    }

    @objc func showCompanion() {
        guard let app = companion else {
            note("pocket spotify app show requested app=\(spec.id) running=false")
            return ensureCompanion(reason: "menu")
        }
        showingCompanion = true
        let shown = app.unhide() && app.activate()
        note("pocket spotify app shown app=\(spec.id) pid=\(app.processIdentifier) ok=\(shown)")
    }

    @objc func reclaim() {
        claimed = false
        note("pocket spotify claim requested app=\(spec.id) source=menu running=\(companion != nil)")
        companion == nil ? ensureCompanion(reason: "menu") : runClaim(attempt: 0)
    }
}
