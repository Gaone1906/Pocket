import AppKit
import Carbon
import SwiftUI

final class ShortcutRecorder: ObservableObject {
    struct Target: Equatable {
        let app: String
        let old: Shortcut?
    }

    @Published private(set) var target: Target?
    private var monitor: Any?

    func isRecording(_ app: String, _ old: Shortcut?) -> Bool {
        target == Target(app: app, old: old)
    }

    func start(_ app: String, old: Shortcut?) {
        stop()
        target = Target(app: app, old: old)
        AppDelegate.shared.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let target = self.target else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.stop()
            case kVK_Delete, kVK_ForwardDelete:
                if let old = target.old { Layout.shared.replaceShortcut(target.app, old: old, with: nil) }
                self.stop()
            default:
                guard let keys = Shortcut.from(event) else {
                    NSSound.beep()
                    return nil
                }
                Layout.shared.replaceShortcut(target.app, old: target.old, with: keys)
                self.stop()
            }
            return nil
        }
        note("pocket settings shortcut recording app=\(app) replacing=\(old?.display ?? "new")")
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard target != nil else { return }
        target = nil
        AppDelegate.shared.recordingShortcut = false
    }
}

struct ShortcutsSettings: View {
    @ObservedObject var layout: Layout
    let theme: BoardTheme
    @StateObject private var recorder = ShortcutRecorder()

    private var apps: [AppSpec] { catalog.filter { layout.enabled.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard shortcuts")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.ink)
                    Text(layout.hotKeys ? "On everywhere on this Mac" : "Off; the shortcuts below are kept for later")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Toggle("", isOn: $layout.hotKeys)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(theme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
            .boardEdge(16)
            VStack(alignment: .leading, spacing: 10) {
                SettingsTitle(text: "APPS")
                VStack(spacing: 0) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 {
                            Rectangle().fill(theme.line).frame(height: 1).padding(.horizontal, 18)
                        }
                        row(app)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.card))
                .boardEdge(16)
                .opacity(layout.hotKeys ? 1 : 0.55)
                Text("Shortcuts need ⌘, ⌥ or ⌃. Esc cancels, Delete removes the one you clicked. A shortcut used by another app moves to this one. Apps you turned off aren't listed.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .onDisappear { recorder.stop() }
    }

    private func row(_ app: AppSpec) -> some View {
        let keys = layout.keys(for: app.id)
        return HStack(spacing: 12) {
            AppGlyph(id: app.id)
                .foregroundStyle(theme.ink)
                .frame(width: 15, height: 15)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme.pill))
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(layout.spot(of: app.id).map(layout.shelfName) ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                ForEach(keys, id: \.display) { key in
                    ShortcutChip(theme: theme, text: key.display, recording: recorder.isRecording(app.id, key),
                                 tap: { toggle(app.id, key) },
                                 remove: { layout.replaceShortcut(app.id, old: key, with: nil) })
                }
                if recorder.isRecording(app.id, nil) {
                    ShortcutChip(theme: theme, text: "", recording: true, tap: { recorder.stop() }, remove: nil)
                } else {
                    AddShortcutButton(theme: theme, wide: keys.isEmpty) { toggle(app.id, nil) }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func toggle(_ app: String, _ old: Shortcut?) {
        if recorder.isRecording(app, old) { recorder.stop() } else { recorder.start(app, old: old) }
    }
}

private struct ShortcutChip: View {
    let theme: BoardTheme
    let text: String
    let recording: Bool
    let tap: () -> Void
    let remove: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: tap) {
                Text(recording ? "Type keys…" : text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(recording ? theme.accentInk : theme.ink)
                    .padding(.leading, 10)
                    .padding(.trailing, remove == nil || recording ? 10 : 2)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(recording ? "Press the new keys. Esc cancels." : "Click to change")
            if let remove, !recording {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(hovering ? theme.ink : theme.faint)
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 5)
                .help("Remove this shortcut")
            }
        }
        .background(Capsule().fill(recording ? theme.accent.opacity(theme.isDark ? 0.24 : 0.18) : theme.pill))
        .overlay(Capsule().strokeBorder(recording ? theme.accent : theme.line, lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: recording)
    }
}

private struct AddShortcutButton: View {
    let theme: BoardTheme
    let wide: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                if wide {
                    Text("Add shortcut")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(hovering ? theme.accentInk : theme.muted)
            .padding(.horizontal, wide ? 10 : 0)
            .frame(width: wide ? nil : 26, height: 26)
            .overlay(Capsule().strokeBorder(hovering ? theme.accent : theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(wide ? "Add a shortcut that opens this app" : "Add another shortcut")
    }
}
