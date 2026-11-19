import AppKit
import Combine
import SwiftUI

let traySpec = AppSpec(id: "pocket", name: "Pocket", summary: "", symbol: "square.grid.2x2", glyph: nil, hotKey: nil, web: nil)

enum TrayActions {
    static func openSettings() {
        AppDelegate.shared.tray.hide(reason: "switched")
        PocketSettings.shared.show(section: .shelves, source: "shelves")
    }
}

final class TrayApp: PocketApp {
    var height: CGFloat = 460
    var themeWatch: AnyCancellable?

    init() { super.init(spec: traySpec) }

    override var resizable: Bool { false }
    override var defaultSize: NSSize { NSSize(width: TrayView.width, height: clamp(height)) }

    override func makeContent() -> NSView {
        let view = TrayView(layout: Layout.shared, themes: BoardThemeStore.shared, open: { [weak self] id in
            self?.hide(reason: "switched")
            AppDelegate.shared.open(id, source: "dropdown")
        }, fit: { [weak self] wanted in
            self?.fit(wanted)
        })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.appearance = BoardThemeStore.shared.theme.appearance
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak hosting] theme in hosting?.appearance = theme.appearance }
        return hosting
    }

    override func show(anchor: NSStatusItem?, source: String) {
        let panel = self.panel
        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: TrayView.width, height: clamp(height))), display: false)
        super.show(anchor: anchor, source: source)
    }

    func clamp(_ wanted: CGFloat) -> CGFloat {
        let area = (panelIfLoaded?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        return min(max(wanted, 220), area - 24)
    }

    func fit(_ wanted: CGFloat) {
        guard abs(wanted - height) > 0.5 else { return }
        height = wanted
        guard let panel = panelIfLoaded else { return }
        let target = clamp(wanted)
        var frame = panel.frame
        guard abs(frame.height - target) > 0.5 else { return }
        frame.origin.y += frame.height - target
        frame.size.height = target
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        note("pocket dropdown resized height=\(Int(target)) wanted=\(Int(wanted)) shelves=\(Layout.shared.shelves.count)")
    }
}

private struct TrayHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct TrayView: View {
    static let width: CGFloat = 436

    @ObservedObject var layout: Layout
    @ObservedObject var themes: BoardThemeStore
    let open: (String) -> Void
    let fit: (CGFloat) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ShelfList(layout: layout, editing: false, open: open)
                .overlay(alignment: .topTrailing) {
                    TrayRoundButton(symbol: "gearshape", help: "Settings", active: false, size: 24) {
                        TrayActions.openSettings()
                    }
                    .offset(y: -1)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: TrayHeightKey.self, value: proxy.size.height)
                })
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .background(BoardBackdrop(theme: themes.theme).ignoresSafeArea())
        .environment(\.colorScheme, themes.theme.colorScheme)
        .animation(Board.glide, value: layout.shelves)
        .animation(Board.glide, value: layout.bar)
        .animation(Board.glide, value: layout.collapsed)
        .onPreferenceChange(TrayHeightKey.self) { content in
            DispatchQueue.main.async { fit(content) }
        }
        .id(themes.theme.id)
    }
}

struct TrayRoundButton: View {
    let symbol: String
    let help: String
    let active: Bool
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        let icon = Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(active ? Board.accentInk : Board.ink)
            .frame(width: size, height: size)
            .contentShape(Circle())
        Button(action: action) {
            if #available(macOS 26, *) {
                icon.glassEffect(.regular.interactive(), in: Circle())
            } else {
                icon
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(active ? Board.accent : Board.line, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ShelfList: View {
    @ObservedObject var layout: Layout
    let editing: Bool
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShelfSection(layout: layout, spot: .bar, title: "Menu bar", symbol: "menubar.rectangle", apps: layout.bar, editing: editing, open: open)
            ForEach(layout.customShelves) { shelf in
                ShelfSection(layout: layout, spot: .shelf(shelf.id), title: shelf.name, symbol: "rectangle.stack", apps: shelf.apps, editing: editing, open: open)
            }
            if editing {
                NewShelfButton { layout.addShelf() }
            }
            let loose = layout.shelves.last?.apps ?? []
            if editing || !loose.isEmpty {
                ShelfSection(layout: layout, spot: .shelf(Shelf.unorganizedId), title: Shelf.unorganizedName, symbol: "tray", apps: loose, editing: editing, open: open)
            }
        }
    }
}

private struct NewShelfButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New shelf")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(hovering ? Board.accentInk : Board.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 14).fill(Board.column.opacity(hovering ? 1 : 0.55)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hovering ? Board.accent : Board.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ShelfSection: View {
    @ObservedObject var layout: Layout
    let spot: ShelfSpot
    let title: String
    let symbol: String
    let apps: [String]
    let editing: Bool
    let open: (String) -> Void
    @State private var targeted = false

    var shelfId: String? {
        if case .shelf(let id) = spot, id != Shelf.unorganizedId { return id }
        return nil
    }

    var collapsed: Bool { layout.collapsed.contains(spot.label) && !editing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            if !collapsed {
                card
            }
        }
        .dropDestination(for: String.self) { dropped, _ in
            drop(dropped, before: nil)
        } isTargeted: { targeted = $0 }
    }

    var heading: some View {
        HStack(spacing: 7) {
            if editing, let shelfId {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Board.faint)
                    .frame(width: 14, height: 22)
                    .contentShape(Rectangle())
                    .draggable("shelf:\(shelfId)") {
                        Label("Shelf", systemImage: "rectangle.stack").padding(6)
                    }
                    .help("Drag to reorder")
            }
            Button {
                layout.toggleCollapsed(spot.label)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Board.faint)
                        .frame(width: 8)
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Board.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(editing)
            if editing, let shelfId {
                ShelfNameField(layout: layout, id: shelfId, name: title)
            } else {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Board.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if editing, let shelfId {
                let index = layout.customShelves.firstIndex { $0.id == shelfId } ?? 0
                ShelfIconButton(symbol: "arrow.up", help: "Move shelf up", enabled: index > 0) { layout.moveShelf(shelfId, by: -1) }
                ShelfIconButton(symbol: "arrow.down", help: "Move shelf down", enabled: index < layout.customShelves.count - 1) { layout.moveShelf(shelfId, by: 1) }
                ShelfIconButton(symbol: "trash", help: "Delete shelf; its apps move to Unorganized", enabled: true) { layout.deleteShelf(shelfId) }
            } else if editing {
                Text(spot == .bar ? "Always shown" : "New apps land here")
                    .font(.system(size: 10))
                    .foregroundStyle(Board.faint)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
    }

    var card: some View {
        Group {
            if apps.isEmpty {
                Text(placeholder)
                    .font(.system(size: 11))
                    .foregroundStyle(Board.faint)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 84), spacing: 4)], alignment: .leading, spacing: 6) {
                    ForEach(apps, id: \.self) { id in
                        AppTile(layout: layout, id: id, open: open)
                            .dropDestination(for: String.self) { dropped, _ in
                                drop(dropped, before: id)
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
        .boardEdge(16, color: targeted ? Board.accent : Board.line, width: targeted ? 1.5 : 1)
        .shadow(color: Board.shadow, radius: 6, y: 2)
    }

    var placeholder: String {
        switch spot {
        case .bar: return "Drop apps here to pin them in the menu bar"
        case .shelf(let id) where id == Shelf.unorganizedId: return "Everything is organized"
        case .shelf: return "Drop apps here"
        }
    }

    func drop(_ dropped: [String], before target: String?) -> Bool {
        guard let payload = dropped.first else { return false }
        if payload.hasPrefix("shelf:") {
            let moving = String(payload.dropFirst(6))
            guard moving != shelfId else { return false }
            layout.moveShelf(moving, before: shelfId)
            return true
        }
        guard layout.enabled.contains(payload), payload != target else { return false }
        layout.move(payload, to: spot, before: target)
        return true
    }
}

private struct ShelfIconButton: View {
    let symbol: String
    let help: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? Board.muted : Board.faint.opacity(0.5))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Board.theme.pill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

struct ShelfNameField: View {
    @ObservedObject var layout: Layout
    let id: String
    let name: String
    @State private var text = ""

    var body: some View {
        TextField("Shelf name", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Board.ink)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .frame(maxWidth: 170)
            .background(RoundedRectangle(cornerRadius: 6).fill(Board.theme.pill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Board.line, lineWidth: 1))
            .onAppear { text = name }
            .onChange(of: name) { _, value in text = value }
            .onSubmit { layout.renameShelf(id, to: text) }
            .onDisappear { layout.renameShelf(id, to: text) }
    }
}

struct AppTile: View {
    @ObservedObject var layout: Layout
    let id: String
    let open: (String) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(hovering ? Board.accent.opacity(0.22) : Board.theme.pill)
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hovering ? Board.accent.opacity(0.6) : Board.line.opacity(0.6), lineWidth: 1)
                AppGlyph(id: id)
                    .foregroundStyle(hovering ? Board.accentInk : Board.ink)
                    .frame(width: 19, height: 19)
            }
            .frame(width: 42, height: 42)
            .scaleEffect(hovering ? 1.06 : 1)
            Text(spec(id)?.name ?? id)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Board.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 76, height: 70)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { open(id) }
        .draggable(id) {
            AppGlyph(id: id).frame(width: 28, height: 28)
        }
        .contextMenu { MoveMenu(layout: layout, id: id) }
        .help(spec(id)?.summary ?? "")
    }
}

struct MoveMenu: View {
    @ObservedObject var layout: Layout
    let id: String

    var body: some View {
        let current = layout.spot(of: id)
        let spots: [ShelfSpot] = [.bar] + layout.shelves.map { .shelf($0.id) }
        Menu("Move to") {
            ForEach(spots.filter { $0 != current }, id: \.label) { spot in
                Button(layout.shelfName(spot)) { layout.move(id, to: spot) }
            }
        }
        Button("New shelf with \(spec(id)?.name ?? id)") {
            layout.move(id, to: .shelf(layout.addShelf(named: spec(id)?.name ?? "New shelf")))
        }
    }
}

extension ShelfSpot {
    var label: String {
        switch self {
        case .bar: return "bar"
        case .shelf(let id): return id
        }
    }
}

struct AppGlyph: View {
    let id: String

    var body: some View {
        if let spec = spec(id), let image = AppIcon.glyph(spec) {
            Image(nsImage: templated(image))
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "questionmark.square")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    func templated(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.isTemplate = true
        return copy
    }
}
