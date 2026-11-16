import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = AppDelegate()
    let layout = Layout.shared
    let bar = BarController()
    let hotKeys = HotKeys()
    let otp = OtpWatcher()
    lazy var mail = MailWatcher(otp: otp)
    var apps: [String: PocketApp] = [:]
    lazy var tray = TrayApp()
    var otpRunning = false
    var awake: NSObjectProtocol?
    var recordingShortcut = false {
        didSet { sync() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            note("pocket notification permission granted=\(granted) error=\(error?.localizedDescription ?? "-")")
        }
        layout.onChange = { [weak self] in self?.sync() }
        sync()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            note("pocket mac woke; checking pages")
            self?.apps.values.compactMap { $0 as? WebApp }.forEach { $0.checkHealth() }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(remoteToggle(_:)),
                                                            name: Notification.Name("com.pranav.pocket.toggle"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(remoteRestart(_:)),
                                                            name: Notification.Name("com.pranav.pocket.restart"), object: nil)
        PocketServer.shared.start()
        if !layout.setupDone { SetupController.shared.present() }
        note("pocket started apps=\(layout.enabled.joined(separator: ","))")
    }

    func sync() {
        let wanted = layout.enabled
        for (id, app) in apps where !wanted.contains(id) {
            app.stop()
            apps[id] = nil
        }
        for id in wanted where apps[id] == nil {
            guard let spec = spec(id), let app = makeApp(spec) else {
                note("pocket app unavailable app=\(id)")
                continue
            }
            app.onDisplayChange = { [weak self] app in self?.bar.refresh(app.spec.id) }
            apps[id] = app
            app.start()
        }
        bar.sync(layout.bar.filter { apps[$0] != nil })
        hotKeys.register(layout.hotKeys && !recordingShortcut ? wanted.compactMap { id in layout.shortcuts[id].map { (id, $0) } } : [])
        syncOtp()
        syncAwake()
    }

    func syncAwake() {
        let needed = apps.values.contains { ($0 as? WebApp)?.site.realtime == true }
        guard needed != (awake != nil) else { return }
        if needed {
            awake = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "keep realtime web apps connected")
        } else if let awake {
            ProcessInfo.processInfo.endActivity(awake)
            self.awake = nil
        }
        note("pocket app nap \(needed ? "blocked for realtime apps" : "allowed")")
    }

    func syncOtp() {
        guard layout.otp != otpRunning else { return }
        otpRunning = layout.otp
        if otpRunning {
            otp.start()
            mail.start()
        } else {
            mail.stop()
            otp.stop()
        }
        note("pocket otp watching=\(otpRunning)")
    }

    func app(_ id: String) -> PocketApp? { apps[id] }

    func anchor(for id: String) -> NSStatusItem { bar.anchor(for: id) }

    func open(_ id: String, source: String) {
        guard let app = apps[id] else { return note("pocket open ignored app=\(id) source=\(source) cause=not enabled") }
        app.toggle(anchor: anchor(for: id), source: source)
    }

    func hideOthers(except keep: PocketApp) {
        (Array(apps.values) + [tray]).filter { $0 !== keep }.forEach { $0.hide(reason: "switched") }
    }

    func appendCommonItems(to menu: NSMenu, for id: String?) {
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        if let id, layout.enabled.contains(id) {
            let toBar = !layout.inBar(id)
            let move = NSMenuItem(title: toBar ? "Move to menu bar" : "Move to dropdown", action: #selector(moveFromMenu(_:)), keyEquivalent: "")
            move.target = self
            move.representedObject = id
            menu.addItem(move)
        }
        menu.addItem(withTitle: "Set up Pocket…", action: #selector(presentSetup), keyEquivalent: "").target = self
        menu.addItem(.separator())
        if layout.otp && mail.available {
            menu.addItem(withTitle: "Add Gmail account for codes…", action: #selector(MailWatcher.addAccount), keyEquivalent: "").target = mail
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Quit Pocket", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    @objc func moveFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        layout.move(id, toBar: !layout.inBar(id))
    }

    @objc func presentSetup() {
        tray.hide(reason: "switched")
        SetupController.shared.present()
    }

    @objc func remoteToggle(_ notification: Notification) {
        guard let id = notification.object as? String else { return }
        open(id, source: "remote")
    }

    @objc func remoteRestart(_ notification: Notification) {
        guard let id = notification.object as? String, let web = apps[id] as? WebApp else {
            return note("pocket remote restart ignored app=\(notification.object as? String ?? "-")")
        }
        web.restart(reason: "remote")
    }

    func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "Pocket")
        main.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plain = edit.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["app"] as? String, let app = apps[id] {
            app.show(anchor: anchor(for: id), source: "notification")
        }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
