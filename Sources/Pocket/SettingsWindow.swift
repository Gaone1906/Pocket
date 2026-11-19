import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case shelves
    case shortcuts
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .shelves: "Shelves"
        case .shortcuts: "Shortcuts"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .shelves: "square.grid.2x2"
        case .shortcuts: "command"
        case .general: "gearshape"
        }
    }
}

final class SettingsFocus: ObservableObject {
    @Published var reveal: String?
    @Published var section: SettingsSection {
        didSet {
            guard section != oldValue else { return }
            note("pocket settings section=\(section.rawValue) previous=\(oldValue.rawValue)")
        }
    }

    init(section: SettingsSection) {
        self.section = section
    }
}

final class PocketSettings: NSObject, NSWindowDelegate {
    static let shared = PocketSettings()

    private var window: NSWindow?
    private var themeWatch: AnyCancellable?
    private let focus = SettingsFocus(section: .appearance)

    @objc func showFromMenu() {
        show(section: nil, source: "menu")
    }

    func show(section: SettingsSection?, source: String = "dropdown", reveal: String? = nil) {
        if let section { focus.section = section }
        focus.reveal = reveal
        AppDelegate.shared.tray.hide(reason: "switched")
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("pocket settings refocused section=\(focus.section.rawValue) source=\(source)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Pocket Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = Board.theme.appearance
        window.backgroundColor = NSColor(Board.backdrop)
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = NSHostingView(rootView: PocketSettingsView(focus: focus))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("pocket.settings")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("pocket settings opened section=\(focus.section.rawValue) source=\(source) theme=\(Board.theme.id)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.delegate = nil
        window = nil
        themeWatch = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("pocket settings closed otherWindows=\(others)")
    }
}

struct SettingsTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Board.muted)
    }
}

struct PocketSettingsView: View {
    @ObservedObject var focus: SettingsFocus
    @ObservedObject var themes = BoardThemeStore.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Board.line).frame(width: 1)
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        detail
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 44)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .onAppear { reveal(reader) }
                .onChange(of: focus.section) { _, _ in reveal(reader) }
                .onChange(of: focus.reveal) { _, _ in reveal(reader) }
            }
        }
        .animation(Board.glide, value: focus.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: themes.theme))
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
        .tint(themes.theme.accent)
    }

    private func reveal(_ reader: ScrollViewProxy) {
        guard focus.section == .appearance else { return }
        if let target = focus.reveal {
            DispatchQueue.main.async {
                withAnimation(Board.glide) { reader.scrollTo(target, anchor: .top) }
                focus.reveal = nil
            }
            return
        }
        guard themes.theme.isDark else { return }
        let id = themes.theme.id
        DispatchQueue.main.async { reader.scrollTo(id, anchor: .center) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pocket")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Board.ink)
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            ForEach(SettingsSection.allCases) { section in
                row(section)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(themes.theme.swatchStyle)
                    .overlay(Circle().stroke(themes.theme.swatchEdge, lineWidth: 1))
                    .frame(width: 14, height: 14)
                Text(themes.theme.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Board.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 52)
        .padding(.bottom, 20)
        .frame(width: 210, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(themes.theme.panel)
    }

    private func row(_ section: SettingsSection) -> some View {
        let on = focus.section == section
        return Button {
            focus.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? Board.ink : Board.muted)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(on ? Board.accent.opacity(themes.theme.isDark ? 0.22 : 0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(focus.section.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Board.ink)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Board.muted)
        }
        .padding(.bottom, 26)
    }

    private var caption: String {
        switch focus.section {
        case .appearance: "One theme for Pocket and its apps. Orario, Aurelius and Kairos keep their own colour, and Gmail, WhatsApp, Slack and Spotify their own look."
        case .shelves: "Arrange where each app lives."
        case .shortcuts: "Open any app from anywhere. Click a shortcut to change it, or + to add another."
        case .general: "Apps, codes and startup."
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch focus.section {
        case .appearance:
            ThemeGallery(themes: themes)
        case .shelves:
            ShelvesSettings()
                .id(themes.theme.id)
        case .shortcuts:
            ShortcutsSettings(layout: Layout.shared, theme: themes.theme)
        case .general:
            GeneralSettings(layout: Layout.shared, theme: themes.theme)
        }
    }
}

private struct ThemeGallery: View {
    @ObservedObject var themes: BoardThemeStore

    private let families = ["Light", "Dark"]
    private let columns = [GridItem(.adaptive(minimum: 172, maximum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(families, id: \.self) { family in
                VStack(alignment: .leading, spacing: 12) {
                    SettingsTitle(text: family.uppercased())
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(BoardTheme.all.filter { $0.family == family }) { theme in
                            ThemeCard(theme: theme, current: themes.theme) {
                                withAnimation(.easeInOut(duration: 0.15)) { themes.theme = theme }
                            }
                            .id(theme.id)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                SettingsTitle(text: "FOLLOWS THE THEME")
                ThemedAppStrip(theme: themes.theme)
            }
            VStack(alignment: .leading, spacing: 12) {
                SettingsTitle(text: "APP COLOURS")
                AppColourList(theme: themes.theme)
            }
            .id("app-colours")
        }
    }
}

private struct AppColourList: View {
    let theme: BoardTheme
    @ObservedObject private var apps = AppThemeStore.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(AppThemeStore.apps.filter { spec($0.id) != nil }.enumerated()), id: \.element.id) { index, app in
                if index > 0 { Rectangle().fill(theme.line).frame(height: 1) }
                AppColourRow(app: app, theme: theme, apps: apps)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
        .boardEdge(16, color: theme.line)
        .frame(maxWidth: 620, alignment: .leading)
    }
}

private struct AppColourRow: View {
    let app: ThemedApp
    let theme: BoardTheme
    @ObservedObject var apps: AppThemeStore

    var body: some View {
        let current = apps.theme(for: app.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppGlyph(id: app.id)
                    .foregroundStyle(apps.iconColor(for: app.id, onDark: theme.isDark) ?? theme.ink)
                    .frame(width: 16, height: 16)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(theme.pill))
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(apps.isDefault(app.id) ? "\(current.name), as on the web" : current.name)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.muted)
                }
                Spacer(minLength: 0)
                if !apps.isDefault(app.id), let fallback = BoardTheme.all.first(where: { $0.id == app.fallback }) {
                    Button("Use \(fallback.name)") {
                        withAnimation(.easeInOut(duration: 0.15)) { apps.set(fallback, for: app.id) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accentInkStyle)
                }
            }
            HStack(spacing: 7) {
                ForEach(BoardTheme.all) { option in
                    AppColourSwatch(option: option, on: option == current, ring: theme.accentInk) {
                        withAnimation(.easeInOut(duration: 0.15)) { apps.set(option, for: app.id) }
                    }
                    if option.id == BoardTheme.all.last(where: { !$0.isDark })?.id {
                        Rectangle().fill(theme.line).frame(width: 1, height: 16).padding(.horizontal, 3)
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct AppColourSwatch: View {
    let option: BoardTheme
    let on: Bool
    let ring: Color
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            Circle()
                .fill(option.swatchStyle)
                .overlay(Circle().stroke(option.swatchEdge, lineWidth: 1))
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay(Circle().stroke(on ? ring : .clear, lineWidth: 2))
                .scaleEffect(hovering && !on ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(option.name)
    }
}

private struct ThemeCard: View {
    let theme: BoardTheme
    let current: BoardTheme
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        let on = theme == current
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 9) {
                ThemePreview(theme: theme)
                    .frame(height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line.opacity(0.9), lineWidth: 1))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(on ? current.accentInk : .clear, lineWidth: 2))
                    .scaleEffect(hovering && !on ? 1.015 : 1)
                HStack(spacing: 6) {
                    Text(theme.name)
                        .font(.system(size: 12, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? current.ink : current.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(current.accentInkStyle)
                    }
                }
                .padding(.horizontal, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(theme.name)
    }
}

private struct ThemePreview: View {
    let theme: BoardTheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.backdrop
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(theme.muted.opacity(0.55)).frame(width: 20, height: 3)
                    Text("3.2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.accentInkStyle)
                    Capsule().fill(theme.faint.opacity(0.6)).frame(width: 16, height: 3)
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .frame(width: 40, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(theme.sidebar)
                HStack(alignment: .top, spacing: 6) {
                    column(0, rows: 3)
                    column(1, rows: 2)
                    column(2, rows: 1)
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Capsule()
                .fill(theme.accentStyle)
                .frame(width: 30, height: 9)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func column(_ index: Int, rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(theme.projectTint(index)).frame(width: 5, height: 5)
                Capsule().fill(theme.ink.opacity(0.75)).frame(maxWidth: 18).frame(height: 3)
            }
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(theme.projectTint(index).opacity(theme.isDark ? 0.8 : 0.55))
                    .frame(height: 6)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.line.opacity(0.8), lineWidth: 0.5))
    }
}

private struct ThemedAppStrip: View {
    let theme: BoardTheme

    private var apps: [AppSpec] { catalog.filter { $0.web == nil && $0.link == nil && !AppThemeStore.isThemed($0.id) } }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(apps, id: \.id) { app in
                HStack(spacing: 6) {
                    Image(systemName: app.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accentInkStyle)
                    Text(app.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule().fill(theme.card))
                .overlay(Capsule().stroke(theme.line, lineWidth: 1))
            }
        }
    }
}

private final class LoginItem: ObservableObject {
    @Published var on = SMAppService.mainApp.status == .enabled

    func set(_ value: Bool) {
        let service = SMAppService.mainApp
        do {
            if value { try service.register() } else { try service.unregister() }
            note("pocket settings login item on=\(value) status=\(service.status.rawValue)")
        } catch {
            note("pocket settings login item failed on=\(value) error=\(error.localizedDescription)")
        }
        on = service.status == .enabled
    }
}

private struct GeneralSettings: View {
    @ObservedObject var layout: Layout
    let theme: BoardTheme
    @StateObject private var login = LoginItem()
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 0) {
                toggle("One-time codes", "Show codes from Messages in the menu bar", isOn: $layout.otp)
                hairline
                toggle("Open at login", "Start Pocket when you sign in", isOn: Binding(get: { login.on }, set: { login.set($0) }))
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
            .boardEdge(16)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apps")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.ink)
                    Text("\(layout.enabled.count) of \(catalog.count) turned on")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Button {
                    AppDelegate.shared.presentSetup()
                } label: {
                    Text("Set up…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentInkStyle)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(theme.accent.opacity(theme.isDark ? 0.2 : 0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
            .boardEdge(16)
            UpdateCard(updater: updater, theme: theme)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var hairline: some View {
        Rectangle().fill(theme.line).frame(height: 1).padding(.horizontal, 18)
    }

    private func toggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

private struct UpdateCard: View {
    @ObservedObject var updater: Updater
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Pocket")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.ink)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if updater.running {
                    ProgressView().controlSize(.small)
                }
                Button {
                    updater.start()
                } label: {
                    Text(updater.running ? "Updating…" : "Update")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentInkStyle)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(theme.accent.opacity(theme.isDark ? 0.2 : 0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(updater.running)
                .opacity(updater.running ? 0.6 : 1)
                .help("Pull the latest main, rebuild and relaunch Pocket")
            }
            if updater.running, !updater.lastLine.isEmpty {
                Text(updater.lastLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if case let .failed(message, detail) = updater.phase {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(theme.isDark ? 0.14 : 0.08)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
        .boardEdge(16)
    }

    private var status: String {
        let build = updater.installed.map { "Build \($0)" } ?? "Unknown build"
        switch updater.phase {
        case .idle: return "\(build). Pulls the latest main, rebuilds and relaunches."
        case let .working(step): return step
        case .upToDate: return "\(build) is the latest main. Nothing to do."
        case .failed: return "\(build). Nothing was installed."
        }
    }
}

struct ThemeLinkRow: View {
    @ObservedObject var themes = AppThemeStore.shared
    let app: String

    var body: some View {
        let theme = themes.theme(for: app)
        Button {
            PocketSettings.shared.show(section: .appearance, source: app, reveal: "app-colours")
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(theme.swatchStyle)
                    .overlay(Circle().stroke(theme.swatchEdge, lineWidth: 1))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text("Change in Pocket Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Pocket Settings")
    }
}
