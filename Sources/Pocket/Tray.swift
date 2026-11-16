import AppKit
import SwiftUI

let traySpec = AppSpec(id: "pocket", name: "Pocket", summary: "", symbol: "square.grid.2x2", glyph: nil, hotKey: nil, web: nil)

final class TrayApp: PocketApp {
    init() { super.init(spec: traySpec) }

    override var resizable: Bool { false }
    override var defaultSize: NSSize { NSSize(width: 392, height: 404) }

    override func makeContent() -> NSView {
        NSHostingView(rootView: TrayView(layout: Layout.shared) { [weak self] id in
            self?.hide(reason: "switched")
            AppDelegate.shared.open(id, source: "dropdown")
        })
    }
}

struct TrayView: View {
    @ObservedObject var layout: Layout
    let open: (String) -> Void
    @State private var hovering: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(title: "Menu bar", ids: layout.bar, toBar: true)
            section(title: "Dropdown", ids: layout.tray, toBar: false)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("Drag icons between rows. Click one to open it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Set up…") { AppDelegate.shared.presentSetup() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .frame(width: 392, height: 404, alignment: .top)
    }

    func section(title: String, ids: [String], toBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    tile(id)
                        .dropDestination(for: String.self) { dropped, _ in
                            drop(dropped, toBar: toBar, before: id)
                        }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay {
                if ids.isEmpty {
                    Text(toBar ? "Drop apps here to pin them in the menu bar" : "Drop apps here to tuck them away")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .dropDestination(for: String.self) { dropped, _ in
                drop(dropped, toBar: toBar, before: nil)
            }
        }
    }

    func tile(_ id: String) -> some View {
        VStack(spacing: 4) {
            icon(id)
                .frame(width: 22, height: 22)
            Text(spec(id)?.name ?? id)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .frame(width: 64, height: 56)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering == id ? Color.accentColor.opacity(0.18) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 ? id : (hovering == id ? nil : hovering) }
        .onTapGesture { open(id) }
        .draggable(id) {
            icon(id).frame(width: 28, height: 28)
        }
        .help(spec(id)?.summary ?? "")
    }

    @ViewBuilder
    func icon(_ id: String) -> some View {
        if let spec = spec(id), let image = AppIcon.glyph(spec) {
            Image(nsImage: templated(image))
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "questionmark.square")
        }
    }

    func templated(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.isTemplate = true
        return copy
    }

    func drop(_ dropped: [String], toBar: Bool, before target: String?) -> Bool {
        guard let id = dropped.first, layout.enabled.contains(id), id != target else { return false }
        layout.move(id, toBar: toBar, before: target)
        return true
    }
}
