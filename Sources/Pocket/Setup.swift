import AppKit
import Carbon
import EventKit
import ServiceManagement
import SwiftUI

private let firstRunTray: Set<String> = ["calendar", "todo", "pomodoro", "calculator", "stats"]

private func shortcutHint() -> String {
    let parts = catalog.compactMap { app in Layout.shared.shortcuts[app.id].map { "\($0.display) \(app.name)" } }
    return "Keyboard shortcuts (\(parts.prefix(2).joined(separator: ", ")) …)"
}

private enum Placement: Int { case bar, tray }

private final class SetupModel: ObservableObject {
    @Published var step = 1
    @Published var picks: [String: Placement] = [:]
    @Published var loginItem = SMAppService.mainApp.status == .enabled
    @Published var loginStatus = SetupModel.describe(SMAppService.mainApp.status)
    @Published var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    let store = EKEventStore()
    var onDone: () -> Void = {}

    init() {
        let layout = Layout.shared
        let firstRun = layout.enabled.isEmpty
        for app in catalog {
            if layout.inBar(app.id) {
                picks[app.id] = .bar
            } else if layout.tray.contains(app.id) {
                picks[app.id] = .tray
            } else if firstRun && firstRunTray.contains(app.id) {
                picks[app.id] = .tray
            }
        }
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "Opens at login"
        case .requiresApproval: return "Waiting for approval in System Settings"
        case .notRegistered: return "Off"
        case .notFound: return "Unavailable"
        @unknown default: return "Unknown"
        }
    }

    func setLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
            note("pocket setup login item on=\(on) status=\(service.status.rawValue)")
        } catch {
            note("pocket setup login item failed on=\(on) error=\(error.localizedDescription)")
        }
        loginItem = service.status == .enabled
        loginStatus = SetupModel.describe(service.status)
    }

    func apply() {
        let layout = Layout.shared
        let chosen = catalog.map(\.id).filter { picks[$0] != nil }
        func group(_ placement: Placement, existing: [String]) -> [String] {
            let members = chosen.filter { picks[$0] == placement }
            let kept = existing.filter(members.contains)
            return kept + members.filter { !kept.contains($0) }
        }
        let bar = group(.bar, existing: layout.bar)
        let tray = group(.tray, existing: layout.tray)
        note("pocket setup applied bar=\(bar.joined(separator: ",")) tray=\(tray.joined(separator: ","))")
        layout.apply(bar: bar, tray: tray)
        step = 2
    }

    func requestCalendar() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                let status = EKEventStore.authorizationStatus(for: .event)
                note("pocket setup calendar access granted=\(granted) status=\(status.rawValue) error=\(error?.localizedDescription ?? "none")")
                self?.calendarStatus = status
            }
        }
    }

    func openSettings(_ url: String) {
        guard let target = URL(string: url) else { return }
        let opened = NSWorkspace.shared.open(target)
        note("pocket setup opened settings url=\(url) opened=\(opened)")
    }

    func signIn(_ id: String) {
        guard let app = AppDelegate.shared.app(id) else {
            note("pocket setup sign in failed app=\(id) reason=app not running")
            return
        }
        note("pocket setup sign in app=\(id)")
        app.show(anchor: nil, source: "setup")
    }
}

private struct AppRow: View {
    let app: AppSpec
    @ObservedObject var model: SetupModel

    var body: some View {
        let enabled = Binding(
            get: { model.picks[app.id] != nil },
            set: { model.picks[app.id] = $0 ? (model.picks[app.id] ?? .tray) : nil }
        )
        let placement = Binding(
            get: { model.picks[app.id] ?? .tray },
            set: { model.picks[app.id] = $0 }
        )
        HStack(spacing: 12) {
            AppBadge(app: app)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text(app.summary).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if enabled.wrappedValue {
                Picker("", selection: placement) {
                    Text("Menu bar").tag(Placement.bar)
                    Text("Shelf").tag(Placement.tray)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                ShortcutField(id: app.id)
            }
            Toggle("", isOn: enabled).toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

private struct ShortcutField: View {
    let id: String
    @ObservedObject var layout = Layout.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 2) {
            Button(action: toggle) {
                Text(recording ? "Type keys…" : layout.shortcuts[id]?.display ?? "Shortcut")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(recording ? .accentColor : layout.shortcuts[id] == nil ? .secondary : .primary)
                    .frame(width: 72)
            }
            .help(recording ? "Press a key with ⌘, ⌥ or ⌃. Esc cancels, Delete clears." : "Click to set a shortcut that opens this app")
            if layout.shortcuts[id] != nil && !recording {
                Button { layout.setShortcut(id, nil) } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove the shortcut")
            }
        }
        .frame(width: 98, alignment: .leading)
        .onDisappear(perform: stop)
    }

    func toggle() {
        recording ? stop() : start()
    }

    func start() {
        stopOthers()
        recording = true
        AppDelegate.shared.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete, kVK_ForwardDelete:
                layout.setShortcut(id, nil)
                stop()
            default:
                guard let keys = Shortcut.from(event) else {
                    NSSound.beep()
                    return nil
                }
                layout.setShortcut(id, keys)
                stop()
            }
            return nil
        }
        ShortcutField.active = stop
    }

    func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        ShortcutField.active = nil
        AppDelegate.shared.recordingShortcut = false
    }

    func stopOthers() {
        ShortcutField.active?()
    }

    static var active: (() -> Void)?
}

private struct AppBadge: View {
    let app: AppSpec

    var body: some View {
        Group {
            if let glyph = AppIcon.glyph(app) {
                Image(nsImage: glyph).resizable().scaledToFit().padding(6)
            } else {
                Image(systemName: app.symbol).font(.system(size: 17)).foregroundColor(.accentColor)
            }
        }
        .frame(width: 32, height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
    }
}

private struct ChooseStep: View {
    @ObservedObject var model: SetupModel
    @ObservedObject var layout = Layout.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(Array(catalog.enumerated()), id: \.element.id) { index, app in
                                AppRow(app: app, model: model)
                                if index < catalog.count - 1 { Divider() }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    GroupBox(label: Text("Extras").font(.headline)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(shortcutHint(), isOn: $layout.hotKeys)
                            Toggle("Show one-time codes from Messages in the menu bar (needs Full Disk Access)", isOn: $layout.otp)
                            Toggle("Open Pocket at login", isOn: Binding(get: { model.loginItem }, set: { model.setLogin($0) }))
                            Text(model.loginStatus).font(.caption).foregroundColor(.secondary).padding(.leading, 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text("Drag apps between the menu bar and your shelves any time from the Pocket icon.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Continue") { model.apply() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }
}

private struct PermissionRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let trailing: Trailing

    init(symbol: String, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 6)
    }
}

private struct SignInStep: View {
    @ObservedObject var model: SetupModel
    @ObservedObject var layout = Layout.shared

    var webApps: [AppSpec] { catalog.filter { $0.web != nil && layout.enabled.contains($0.id) } }
    var calendarOn: Bool { layout.enabled.contains("calendar") }
    var calendarGranted: Bool { model.calendarStatus == .fullAccess }
    var calendarDenied: Bool { model.calendarStatus == .denied || model.calendarStatus == .restricted || model.calendarStatus == .writeOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if webApps.isEmpty && !calendarOn && !layout.otp {
                        Text("Nothing to sign in to").foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        GroupBox {
                            VStack(spacing: 0) {
                                ForEach(webApps, id: \.id) { app in
                                    HStack(spacing: 12) {
                                        AppBadge(app: app)
                                        Text(app.name).font(.headline)
                                        Spacer()
                                        Button("Sign in") { model.signIn(app.id) }
                                    }
                                    .padding(.vertical, 6)
                                    Divider()
                                }
                                if calendarOn {
                                    PermissionRow(symbol: "calendar", title: "Calendar access", detail: calendarDetail) {
                                        if calendarGranted {
                                            Label("Granted", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                                        } else if calendarDenied {
                                            Button("Open Settings") {
                                                model.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                                            }
                                        } else {
                                            Button("Allow access") { model.requestCalendar() }
                                        }
                                    }
                                    if layout.otp { Divider() }
                                }
                                if layout.otp {
                                    PermissionRow(symbol: "lock.shield", title: "Full Disk Access",
                                                  detail: "Needed to read one-time codes from Messages. Open the setting and add Pocket to the list.") {
                                        Button("Open Settings") {
                                            model.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text("Drag apps between the menu bar and your shelves any time from the Pocket icon.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Back") { model.step = 1 }
                Button("Done") { model.onDone() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    var calendarDetail: String {
        if calendarGranted { return "Pocket can read the events in your Calendar." }
        if calendarDenied { return "Access is off. Enable Pocket under Privacy & Security > Calendars." }
        return "Lets the Calendar app show your events."
    }
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.step == 1 ? "Choose your apps" : "Sign in & permissions").font(.title2.weight(.semibold))
                Text(model.step == 1 ? "Step 1 of 2" : "Step 2 of 2").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 20)
            if model.step == 1 { ChooseStep(model: model) } else { SignInStep(model: model) }
        }
        .frame(minWidth: 720, minHeight: 640)
    }
}

final class SetupController: NSObject, NSWindowDelegate {
    static let shared = SetupController()
    private var window: NSWindow?
    private var model: SetupModel?

    func present() {
        if let window {
            note("pocket setup refocused")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = SetupModel()
        model.onDone = { [weak self] in self?.finish() }
        let host = NSHostingView(rootView: SetupView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set up Pocket"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        note("pocket setup opened")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        Layout.shared.setupDone = true
        note("pocket setup done enabled=\(Layout.shared.enabled.joined(separator: ","))")
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        note("pocket setup closed done=\(Layout.shared.setupDone)")
        window?.delegate = nil
        window = nil
        model = nil
    }
}
