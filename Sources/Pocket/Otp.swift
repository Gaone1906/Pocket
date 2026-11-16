import AppKit
import SQLite3

final class OtpWatcher {
    static let keywords = ["otp", "one time", "one-time", "verification", "code", "passcode", "pin", "password"]
    static let digits = try! NSRegularExpression(pattern: #"(?<![\d.,:/-])\d{4,8}(?![\d]|[.,:/]\d)"#)
    let path = NSHomeDirectory() + "/Library/Messages/chat.db"
    let showFor: TimeInterval = 30
    var db: OpaquePointer?
    var lastRow: Int64 = -1
    var lastError = ""
    let walPath = NSHomeDirectory() + "/Library/Messages/chat.db-wal"
    var started = false
    var stopped = false
    var walSource: DispatchSourceFileSystemObject?
    var debounce: DispatchWorkItem?
    var rearm: DispatchWorkItem?
    var fallbackTimer: Timer?
    var safetyTimer: Timer?
    var keepTimer: Timer?
    var terminateObserver: NSObjectProtocol?
    var watchState = ""
    var item: NSStatusItem?
    var code = ""
    var hideWork: DispatchWorkItem?

    static let messagesId = "com.apple.MobileSMS"

    func start() {
        guard !started else { return }
        started = true
        stopped = false
        let safety = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.poll() }
        safety.tolerance = 10
        safetyTimer = safety
        arm()
        poll()
        keepMessages(reason: "startup")
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard (event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == OtpWatcher.messagesId else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.keepMessages(reason: "quit") }
        }
        let check = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.keepMessages(reason: "check") }
        check.tolerance = 20
        keepTimer = check
    }

    func stop() {
        guard started else { return }
        started = false
        stopped = true
        debounce?.cancel()
        debounce = nil
        rearm?.cancel()
        rearm = nil
        walSource?.cancel()
        walSource = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        safetyTimer?.invalidate()
        safetyTimer = nil
        keepTimer?.invalidate()
        keepTimer = nil
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
        terminateObserver = nil
        hideWork?.cancel()
        hide(reason: "stopped")
        sqlite3_close(db)
        db = nil
        lastRow = -1
        watchState = ""
        note("pocket otp watcher stopped")
    }

    func transition(_ state: String, detail: String) {
        guard state != watchState else { return }
        watchState = state
        note("pocket otp wal watch \(state) path=\(walPath) \(detail)")
    }

    func arm() {
        guard !stopped else { return }
        rearm = nil
        walSource?.cancel()
        walSource = nil
        let fd = open(walPath, O_EVTONLY)
        guard fd >= 0 else {
            let code = errno
            transition("fallback", detail: "errno=\(code) cause=\(String(cString: strerror(code))) retryIn=30s")
            if fallbackTimer == nil {
                let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    self?.arm()
                    self?.poll()
                }
                timer.tolerance = 5
                fallbackTimer = timer
            }
            return
        }
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, !self.stopped, source === self.walSource else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                source.cancel()
                self.walSource = nil
                self.transition("rearming", detail: "events=\(events.rawValue)")
                let work = DispatchWorkItem { [weak self] in self?.arm() }
                self.rearm = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
                return
            }
            self.debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.poll() }
            self.debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
        source.setCancelHandler { close(fd) }
        walSource = source
        source.resume()
        transition("armed", detail: "fd=\(fd)")
    }

    func keepMessages(reason: String) {
        if UserDefaults.standard.object(forKey: "keepMessages") as? Bool == false {
            if reason == "startup" { note("pocket messages keep-open paused by setting keepMessages=false") }
            return
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: OtpWatcher.messagesId).first {
            if reason == "startup", !running.isHidden, !running.isActive { running.hide() }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: OtpWatcher.messagesId) else {
            return note("pocket messages launch skipped reason=\(reason) cause=app not found")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error { note("pocket messages launch failed reason=\(reason) cause=\(error.localizedDescription)") }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { app?.hide() }
                note("pocket messages launched hidden reason=\(reason) pid=\(app?.processIdentifier ?? -1)")
            }
        }
    }

    func fail(_ stage: String) {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
        if message != lastError {
            note("pocket otp watcher blocked stage=\(stage) cause=\(message); needs Full Disk Access for Pocket")
            lastError = message
        }
        sqlite3_close(db)
        db = nil
    }

    func poll() {
        guard !stopped else { return }
        if db == nil, sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK { return fail("open") }
        if lastRow < 0 {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "select ifnull(max(ROWID), 0) from message", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else { sqlite3_finalize(statement); return fail("start") }
            lastRow = sqlite3_column_int64(statement, 0)
            sqlite3_finalize(statement)
            lastError = ""
            note("pocket otp watcher started fromRow=\(lastRow)")
            return
        }
        var statement: OpaquePointer?
        let sql = "select m.ROWID, m.text, m.attributedBody, ifnull(h.id, ''), m.date, m.service from message m left join handle h on h.ROWID = m.handle_id where m.ROWID > ? and m.is_from_me = 0 order by m.ROWID"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return fail("query") }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastRow)
        while sqlite3_step(statement) == SQLITE_ROW {
            lastRow = sqlite3_column_int64(statement, 0)
            let sender = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "-"
            let sent = Date(timeIntervalSinceReferenceDate: Double(sqlite3_column_int64(statement, 4)) / 1_000_000_000)
            let kind = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "-"
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: OtpWatcher.messagesId).isEmpty
            note("pocket message arrived row=\(lastRow) service=\(kind) sender=\(sender) lagSeconds=\(Int(Date().timeIntervalSince(sent))) messagesOpen=\(running)")
            guard let text = OtpWatcher.body(statement) else {
                note("pocket otp skipped row=\(lastRow) sender=\(sender) cause=no readable text")
                continue
            }
            if let found = OtpWatcher.extract(text) {
                show(found, source: "sms row=\(lastRow) sender=\(sender)")
            }
        }
    }

    static func body(_ statement: OpaquePointer?) -> String? {
        if let text = sqlite3_column_text(statement, 1) { return String(cString: text) }
        guard let blob = sqlite3_column_blob(statement, 2) else { return nil }
        let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
        return (NSUnarchiver.unarchiveObject(with: data) as? NSAttributedString)?.string
    }

    static func extract(_ text: String) -> String? {
        let lower = text.lowercased()
        guard keywords.contains(where: lower.contains) else { return nil }
        let whole = text as NSString
        for match in digits.matches(in: text, range: NSRange(location: 0, length: whole.length)) {
            let before = whole.substring(to: match.range.location).lowercased().suffix(5)
            if before.contains("rs") || before.contains("₹") || before.contains("inr") || before.contains("x") { continue }
            return whole.substring(with: match.range)
        }
        return nil
    }

    func show(_ found: String, source: String) {
        code = found
        let item = self.item ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        if let button = item.button {
            button.attributedTitle = NSAttributedString(string: found, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.systemGreen,
            ])
            button.target = self
            button.action = #selector(copyCode)
            button.toolTip = "Click to copy"
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide(reason: "timeout") }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showFor, execute: work)
        note("pocket otp shown \(source) digits=\(found.count) seconds=\(Int(showFor))")
    }

    @objc func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        note("pocket otp copied digits=\(code.count)")
        hide(reason: "copied")
    }

    func hide(reason: String) {
        hideWork?.cancel()
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        code = ""
        note("pocket otp hidden reason=\(reason)")
    }
}
