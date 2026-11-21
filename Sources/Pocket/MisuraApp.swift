import AppKit
import Combine
import SwiftUI

final class MisuraApp: PocketApp {
    override var defaultSize: NSSize { NSSize(width: 380, height: 560) }
    override var minSize: NSSize { NSSize(width: 380, height: 560) }
    override var resizable: Bool { false }

    override func start() {
        let store = MisuraStore.shared
        store.onChange = { [weak self] in self?.changed() }
        note("misura app started day=\(store.today) plan=\(store.plan != nil) entries=\(store.book.entries.count) weights=\(store.book.weights.count)")
    }

    override func stop() {
        MisuraStore.shared.onChange = nil
        super.stop()
    }

    override func makeContent() -> NSView {
        let view = MisuraGlance(store: MisuraStore.shared) { [weak self] in self?.openWindow(source: "dropdown") }
        return ThemedHostingView(rootView: view, app: "calorie")
    }

    override func didShow() {
        MisuraStore.shared.tick()
    }

    override func barTitle() -> NSAttributedString? {
        let store = MisuraStore.shared
        guard let plan = store.plan, plan.menuLeft, let day = store.summary(store.today) else { return nil }
        let left = day.left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: left < 0 ? NSColor.systemRed : NSColor.labelColor
        ]
        return NSAttributedString(string: left < 0 ? " +\(MisuraText.kcal(-left))" : " \(MisuraText.kcal(left)) left", attributes: attributes)
    }

    func openWindow(source: String) {
        hide(reason: "switched")
        MisuraWindow.shared.present(source: source)
    }

    override func menuItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open Terra", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        return [open]
    }

    @objc private func openFromMenu() { openWindow(source: "menu") }
}

enum MisuraLook {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static var onAccent: Color { MisuraBoard.theme.isDark ? MisuraBoard.backdrop : .white }
    static var card: Color { MisuraBoard.theme.isDark ? MisuraBoard.column : Color.white.opacity(0.55) }

    static func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(font(10.5, .semibold))
            .tracking(1.2)
            .foregroundStyle(MisuraBoard.muted)
    }
}

struct MisuraCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(MisuraBoard.column))
            .boardEdge(14)
    }
}

struct MisuraBar: View {
    let value: Double
    var marker: Double? = nil
    var height: CGFloat = 8
    var tint: Color? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MisuraBoard.line.opacity(0.7))
                Capsule().fill(tint ?? MisuraBoard.under)
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .opacity(value <= 0 ? 0 : 1)
                if let marker {
                    Rectangle().fill(MisuraBoard.ink)
                        .frame(width: 2, height: height + 6)
                        .offset(x: geo.size.width * min(1, max(0, marker)) - 1)
                }
            }
        }
        .frame(height: height)
    }
}

struct MisuraRing: View {
    let fraction: Double
    let size: CGFloat
    let line: CGFloat
    var tint: Color? = nil

    var body: some View {
        ZStack {
            Circle().stroke(MisuraBoard.line.opacity(0.7), lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint ?? MisuraBoard.under, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

final class MisuraWindow: NSObject, NSWindowDelegate {
    static let shared = MisuraWindow()

    private var window: NSWindow?
    private var themeWatch: AnyCancellable?

    func present(source: String) {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("misura window refocused source=\(source)")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Terra"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = MisuraBoard.theme.appearance
        window.backgroundColor = NSColor(MisuraBoard.backdrop)
        themeWatch = AppThemeStore.shared.publisher(for: "calorie").sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
        let host = NSHostingView(rootView: MisuraBoardView(store: MisuraStore.shared))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("calorie.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("misura window opened source=\(source) plan=\(MisuraStore.shared.plan != nil)")
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        window?.delegate = nil
        window = nil
        themeWatch = nil
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
        note("misura window closed otherWindows=\(others)")
    }
}

private struct MisuraGlance: View {
    @ObservedObject var store: MisuraStore
    @ObservedObject var themes = AppThemeStore.shared
    let open: () -> Void
    @State private var quick = ""
    @State private var problem = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Terra").font(MisuraLook.font(17, .bold)).foregroundStyle(MisuraBoard.ink)
                Spacer()
                Text(MisuraDays.format(store.today, "EEEdMMM")).font(MisuraLook.font(12)).foregroundStyle(MisuraBoard.muted)
                Button(action: open) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MisuraBoard.muted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(MisuraBoard.line.opacity(0.55)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open Terra")
            }
            if let day = store.summary(store.today) {
                today(day)
            } else {
                Spacer()
                Text("Set your plan to start.")
                    .font(MisuraLook.font(14))
                    .foregroundStyle(MisuraBoard.muted)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
            Button(action: open) {
                Text(store.plan == nil ? "Set up" : "Open")
                    .font(MisuraLook.font(13, .semibold))
                    .foregroundStyle(MisuraLook.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(MisuraBoard.accentInk))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .id(MisuraBoard.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BoardBackdrop(theme: MisuraBoard.theme))
        .ignoresSafeArea()
        .appTheme(MisuraBoard.theme)
    }

    @ViewBuilder private func today(_ day: MisuraDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(MisuraText.kcal(abs(day.left)))
                    .font(MisuraLook.font(40, .bold))
                    .foregroundStyle(day.left < 0 ? MisuraBoard.overInk : MisuraBoard.ink)
                Text(day.left < 0 ? "over" : "left").font(MisuraLook.font(14)).foregroundStyle(MisuraBoard.muted)
                Spacer()
                Text("/ \(MisuraText.kcal(day.budget))").font(MisuraLook.font(15, .semibold)).foregroundStyle(MisuraBoard.ink)
            }
            .monospacedDigit()
            MisuraBar(value: day.eaten / max(1, day.budget), height: 12, tint: day.over ? MisuraBoard.over : nil)
            HStack {
                Text("\(MisuraText.kcal(day.eaten)) eaten")
                Spacer()
                Text("\(MisuraText.kcal(day.workout)) burned").foregroundStyle(MisuraBoard.under).fontWeight(.semibold)
            }
            .font(MisuraLook.font(11.5))
            .foregroundStyle(MisuraBoard.muted)
        }
        HStack(spacing: 8) {
            TextField("Poha 380 · Gym −300", text: $quick)
                .textFieldStyle(.plain)
                .font(MisuraLook.font(13))
                .onSubmit(addQuick)
            Image(systemName: "return").font(.system(size: 11)).foregroundStyle(MisuraBoard.muted)
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(MisuraLook.card))
        .boardEdge(10, color: problem ? MisuraBoard.over : nil)
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.entries(on: store.today)) { entry in
                    HStack {
                        Text(entry.title).lineLimit(1)
                        Spacer()
                        Text(entry.isWorkout ? MisuraText.kcal(-(entry.kcal * (store.plan?.watchShare ?? 1))) : MisuraText.kcal(entry.kcal))
                            .fontWeight(.semibold)
                            .foregroundStyle(entry.isWorkout ? MisuraBoard.under : MisuraBoard.ink)
                    }
                    .font(MisuraLook.font(13))
                    .foregroundStyle(MisuraBoard.ink)
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) { Rectangle().fill(MisuraBoard.line.opacity(0.6)).frame(height: 1) }
                    .contextMenu {
                        Button("Delete") { store.delete(entry.id) }
                    }
                }
            }
            .monospacedDigit()
        }
        .scrollIndicators(.never)
        if let week = store.week(store.today), let month = store.monthLoss(store.today) {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("Week"); Spacer(); Text("\(MisuraText.kcal(week.deficit)) / \(MisuraText.kcal(week.goal))").fontWeight(.semibold) }
                MisuraBar(value: week.deficit / max(1, week.goal), marker: week.due / max(1, week.goal))
                HStack { Text("Month"); Spacer(); Text("\(MisuraText.kg(-month.lost)) / \(MisuraText.kg(-month.target)) kg").fontWeight(.semibold) }
                MisuraBar(value: month.lost / max(0.1, month.target), marker: month.due / max(0.1, month.target))
            }
            .font(MisuraLook.font(12.5))
            .foregroundStyle(MisuraBoard.ink)
            .monospacedDigit()
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(MisuraBoard.sidebar))
        }
    }

    private func addQuick() {
        guard let parsed = MisuraText.parseQuick(quick) else {
            problem = !quick.trimmingCharacters(in: .whitespaces).isEmpty
            return
        }
        store.add(kind: parsed.kind, title: parsed.title, kcal: parsed.kcal)
        quick = ""
        problem = false
    }
}

enum MisuraMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    var id: String { rawValue }
}

struct MisuraBoardView: View {
    @ObservedObject var store: MisuraStore
    @ObservedObject var themes = AppThemeStore.shared
    @State private var mode = MisuraMode.day
    @State private var day = ""
    @State private var sidebar = true
    @State private var settings = false

    private var shown: String { day.isEmpty ? store.today : day }

    var body: some View {
        HStack(spacing: 0) {
            if store.plan != nil && sidebar {
                MisuraSidebar(store: store)
                    .frame(width: 230)
                    .background(MisuraBoard.sidebar)
                Rectangle().fill(MisuraBoard.line).frame(width: 1)
            }
            Group {
                if store.plan == nil {
                    MisuraSetup(store: store)
                } else {
                    main
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if settings && store.plan != nil {
                Rectangle().fill(MisuraBoard.line).frame(width: 1)
                MisuraSettings(store: store)
                    .frame(width: 300)
                    .background(MisuraBoard.sidebar)
                    .transition(.move(edge: .trailing))
            }
        }
        .id(MisuraBoard.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: MisuraBoard.theme))
        .ignoresSafeArea()
        .appTheme(MisuraBoard.theme)
        .font(MisuraLook.font(13))
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { sidebar.toggle() }
                } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 15)).foregroundStyle(MisuraBoard.muted).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(sidebar ? "Hide sidebar" : "Show sidebar")
                MisuraSegment(options: MisuraMode.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { settings.toggle() }
                    note("misura settings \(settings ? "opened" : "closed")")
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(settings ? MisuraLook.onAccent : MisuraBoard.muted)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(settings ? MisuraBoard.accentInk : MisuraBoard.column))
                        .overlay(Circle().stroke(settings ? MisuraBoard.accentInk : MisuraBoard.line, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                .help(settings ? "Close settings" : "Settings")
            }
            .padding(.top, 24)
            switch mode {
            case .day: MisuraDayView(store: store, day: Binding(get: { shown }, set: { day = $0 == store.today ? "" : $0 }))
            case .week: MisuraWeekView(store: store, day: Binding(get: { shown }, set: { day = $0 == store.today ? "" : $0 })) { picked in
                    day = picked == store.today ? "" : picked
                    mode = .day
                }
            case .month: MisuraMonthView(store: store, day: Binding(get: { shown }, set: { day = $0 == store.today ? "" : $0 })) { picked in
                    day = picked == store.today ? "" : picked
                    mode = .day
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }
}

struct MisuraSegment<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                let on = option.1 == selection
                Button {
                    selection = option.1
                } label: {
                    Text(option.0)
                        .font(MisuraLook.font(compact ? 12 : 13, on ? .semibold : .regular))
                        .foregroundStyle(on ? MisuraBoard.ink : MisuraBoard.muted)
                        .padding(.horizontal, compact ? 10 : 16)
                        .frame(height: compact ? 24 : 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? MisuraBoard.backdrop : Color.clear).shadow(color: on ? MisuraBoard.shadow : .clear, radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(MisuraBoard.line.opacity(0.45)))
        .boardEdge(10)
    }
}

private struct MisuraSidebar: View {
    @ObservedObject var store: MisuraStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let day = store.summary(store.today) {
                    MisuraCard {
                        MisuraLook.kicker("Today")
                        figure(day.left < 0 ? "+\(MisuraText.kcal(-day.left))" : MisuraText.kcal(day.left), day.left < 0 ? "/ \(MisuraText.kcal(day.budget))" : "left of \(MisuraText.kcal(day.budget))", over: day.left < 0)
                        MisuraBar(value: day.eaten / max(1, day.budget), tint: day.over ? MisuraBoard.over : nil)
                    }
                }
                if let week = store.week(store.today) {
                    MisuraCard {
                        MisuraLook.kicker("Week")
                        figure(MisuraText.kcal(week.deficit), "/ \(MisuraText.kcal(week.goal))", over: false)
                        MisuraBar(value: week.deficit / max(1, week.goal), marker: week.due / max(1, week.goal))
                    }
                }
                if let month = store.monthLoss(store.today) {
                    MisuraCard {
                        MisuraLook.kicker("Month")
                        figure(MisuraText.kg(-month.lost), "/ \(MisuraText.kg(-month.target)) kg", over: false)
                        MisuraBar(value: month.lost / max(0.1, month.target), marker: month.due / max(0.1, month.target))
                    }
                }
                if let goal = store.goalProgress() {
                    MisuraCard {
                        MisuraLook.kicker("Goal")
                        figure(MisuraText.kg(-goal.lost), "/ \(MisuraText.kg(-goal.total)) kg", over: false)
                        MisuraBar(value: goal.lost / max(0.1, goal.total), marker: goal.due / max(0.1, goal.total))
                        HStack {
                            Text("ETA").foregroundStyle(MisuraBoard.ink)
                            Spacer()
                            Text(MisuraDays.short(goal.eta)).fontWeight(.bold).foregroundStyle(goal.eta > (store.plan?.goalDay ?? goal.eta) ? MisuraBoard.overInk : MisuraBoard.ink)
                        }
                        .font(MisuraLook.font(13))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 40)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    private func figure(_ big: String, _ small: String, over: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(big).font(MisuraLook.font(26, .bold)).foregroundStyle(over ? MisuraBoard.overInk : MisuraBoard.ink)
            Spacer()
            Text(small).font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
        }
        .monospacedDigit()
    }
}

struct MisuraEntryRow: View {
    @ObservedObject var store: MisuraStore
    let entry: MisuraEntry
    var first = false
    @State private var editing = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.title).lineLimit(1).foregroundStyle(MisuraBoard.ink)
            Spacer()
            if hover {
                Button { store.delete(entry.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(MisuraBoard.muted)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            Text(entry.isWorkout ? MisuraText.kcal(entry.kcal * (store.plan?.watchShare ?? 1)) : MisuraText.kcal(entry.kcal))
                .fontWeight(.bold)
                .foregroundStyle(entry.isWorkout ? MisuraBoard.under : MisuraBoard.ink)
                .monospacedDigit()
        }
        .font(MisuraLook.font(13))
        .padding(.vertical, 7)
        .overlay(alignment: .top) { if !first { Rectangle().fill(MisuraBoard.line.opacity(0.6)).frame(height: 1) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { editing = true }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            MisuraEntryEditor(store: store, entry: entry) { editing = false }
        }
    }
}

private struct MisuraEntryEditor: View {
    @ObservedObject var store: MisuraStore
    let entry: MisuraEntry
    let done: () -> Void
    @State private var title = ""
    @State private var kcal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                TextField("kcal", text: $kcal).textFieldStyle(.roundedBorder).frame(width: 90).onSubmit(save)
                Text(entry.isWorkout ? "kcal on the Watch" : "kcal").font(MisuraLook.font(12)).foregroundStyle(MisuraBoard.muted)
            }
            HStack {
                Button("Delete", role: .destructive) {
                    store.delete(entry.id)
                    done()
                }
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            title = entry.title
            kcal = String(Int(entry.kcal))
        }
    }

    private func save() {
        guard let value = Double(kcal.trimmingCharacters(in: .whitespaces)), value > 0 else { return }
        var changed = entry
        changed.title = title
        changed.kcal = value.rounded()
        store.update(changed)
        done()
    }
}

struct MisuraAddRow: View {
    @ObservedObject var store: MisuraStore
    let kind: String
    let day: String
    var slot: MisuraSlot? = nil
    var shortcut: KeyboardShortcut? = nil
    @State private var open = false
    @State private var title = ""
    @State private var kcal = ""
    @FocusState private var focus: Bool

    var body: some View {
        Group {
            if open {
                HStack(spacing: 8) {
                    TextField(kind == "meal" ? "What" : "Workout", text: $title)
                        .textFieldStyle(.plain)
                        .focused($focus)
                        .onSubmit(save)
                    TextField("kcal", text: $kcal)
                        .textFieldStyle(.plain)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(save)
                    Button(action: save) {
                        Image(systemName: "return").font(.system(size: 11, weight: .semibold)).foregroundStyle(MisuraBoard.muted)
                    }
                    .buttonStyle(.plain)
                    Button {
                        open = false
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(MisuraBoard.muted)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                .font(MisuraLook.font(13))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(MisuraLook.card))
                .boardEdge(9)
            } else {
                Button {
                    open = true
                    focus = true
                } label: {
                    HStack {
                        Text("+ Add")
                        Spacer()
                        if let shortcut { Text(label(shortcut)) }
                    }
                    .font(MisuraLook.font(13))
                    .foregroundStyle(MisuraBoard.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MisuraBoard.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(MisuraShortcut(shortcut: shortcut))
            }
        }
        .padding(.top, 4)
    }

    private func label(_ shortcut: KeyboardShortcut) -> String {
        (shortcut.modifiers.contains(.shift) ? "⌘⇧" : "⌘") + String(shortcut.key.character).uppercased()
    }

    private func save() {
        let value = Double(kcal.trimmingCharacters(in: .whitespaces)) ?? MisuraText.parseQuick(title)?.kcal
        guard let value, value > 0 else {
            focus = true
            return
        }
        let name = Double(kcal.trimmingCharacters(in: .whitespaces)) == nil ? (MisuraText.parseQuick(title)?.title ?? title) : title
        store.add(kind: kind, title: name, kcal: value, day: day, slot: slot)
        title = ""
        kcal = ""
        open = false
    }
}

private struct MisuraShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut { content.keyboardShortcut(shortcut) } else { content }
    }
}

private struct MisuraDayView: View {
    @ObservedObject var store: MisuraStore
    @Binding var day: String
    @State private var weightText = ""
    @State private var editingWeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            strip
            Text(MisuraDays.long(day)).font(MisuraLook.font(24, .bold)).foregroundStyle(MisuraBoard.ink)
            HStack(alignment: .top, spacing: 14) {
                meals
                    .frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    if let summary = store.summary(day) { ring(summary) }
                    workouts
                    weight
                }
                .frame(width: 340)
            }
        }
    }

    private var strip: some View {
        HStack(spacing: 6) {
            Button { day = MisuraDays.shift(day, by: -7) } label: { Image(systemName: "chevron.left").foregroundStyle(MisuraBoard.muted).frame(width: 28, height: 28) }
                .buttonStyle(.plain)
            ForEach(MisuraDays.week(day), id: \.self) { key in
                let on = key == day
                Button { day = key } label: {
                    VStack(spacing: 3) {
                        Text(MisuraDays.weekdayShort(key)).font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
                        Text("\(MisuraDays.dayNumber(key))").font(MisuraLook.font(15, .semibold)).foregroundStyle(on ? MisuraBoard.accentInk : MisuraBoard.ink)
                        dot(key)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(on ? MisuraLook.card : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? MisuraBoard.line : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { day = MisuraDays.shift(day, by: 7) } label: { Image(systemName: "chevron.right").foregroundStyle(MisuraBoard.muted).frame(width: 28, height: 28) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(MisuraBoard.column))
        .boardEdge(14)
    }

    @ViewBuilder private func dot(_ key: String) -> some View {
        let summary = store.summary(key)
        if let summary, summary.logged, key < store.today {
            Circle().fill(summary.over ? MisuraBoard.over : MisuraBoard.under).frame(width: 7, height: 7)
        } else {
            Circle().stroke(key == store.today ? MisuraBoard.accentInk : MisuraBoard.line, lineWidth: 1.5).frame(width: 7, height: 7)
        }
    }

    private var meals: some View {
        MisuraCard {
            HStack {
                MisuraLook.kicker("Meals")
                Spacer()
                Text(MisuraText.kcal(store.summary(day)?.eaten ?? 0)).font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MisuraSlot.allCases) { slot in
                    let list = store.meals(on: day, slot: slot)
                    Text(slot.label.uppercased())
                        .font(MisuraLook.font(10.5, .semibold))
                        .tracking(1.1)
                        .foregroundStyle(MisuraBoard.muted)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                        MisuraEntryRow(store: store, entry: entry)
                    }
                    if list.isEmpty || slot == MisuraSlot.now() {
                        MisuraAddRow(store: store, kind: "meal", day: day, slot: slot,
                                     shortcut: slot == MisuraSlot.now() ? KeyboardShortcut("n", modifiers: .command) : nil)
                    }
                }
            }
        }
    }

    private func ring(_ summary: MisuraDay) -> some View {
        MisuraCard {
            HStack(spacing: 16) {
                ZStack {
                    MisuraRing(fraction: summary.eaten / max(1, summary.budget), size: 112, line: 11, tint: summary.over ? MisuraBoard.over : nil)
                    VStack(spacing: 0) {
                        Text(MisuraText.kcal(abs(summary.left))).font(MisuraLook.font(26, .bold)).foregroundStyle(summary.left < 0 ? MisuraBoard.overInk : MisuraBoard.ink)
                        Text(summary.left < 0 ? "over" : "left").font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
                    }
                    .monospacedDigit()
                }
                VStack(spacing: 6) {
                    line("Budget", MisuraText.kcal(summary.budget))
                    line("Eaten", MisuraText.kcal(summary.eaten))
                    line("BMR", MisuraText.kcal(summary.base))
                    line("Workout", MisuraText.kcal(summary.workout), tint: MisuraBoard.under)
                    Rectangle().fill(MisuraBoard.line).frame(height: 1)
                    line("Deficit", MisuraText.kcal(summary.base + summary.workout - summary.eaten))
                }
            }
        }
    }

    private func line(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        HStack {
            Text(title).foregroundStyle(MisuraBoard.ink)
            Spacer()
            Text(value).fontWeight(.bold).foregroundStyle(tint ?? MisuraBoard.ink)
        }
        .font(MisuraLook.font(13))
        .monospacedDigit()
    }

    private var workouts: some View {
        MisuraCard {
            MisuraLook.kicker("Workouts")
            VStack(spacing: 0) {
                ForEach(Array(store.workouts(on: day).enumerated()), id: \.element.id) { index, entry in
                    MisuraEntryRow(store: store, entry: entry, first: index == 0)
                }
                MisuraAddRow(store: store, kind: "workout", day: day, shortcut: KeyboardShortcut("n", modifiers: [.command, .shift]))
            }
        }
    }

    private var weight: some View {
        MisuraCard {
            MisuraLook.kicker("Weight")
            HStack(alignment: .firstTextBaseline) {
                if let kg = store.weight(on: day), !editingWeight {
                    Button {
                        weightText = String(format: "%.1f", kg)
                        editingWeight = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", kg)).font(MisuraLook.font(26, .bold))
                            Text("kg").font(MisuraLook.font(13))
                        }
                        .foregroundStyle(MisuraBoard.ink)
                    }
                    .buttonStyle(.plain)
                } else {
                    TextField("kg", text: $weightText)
                        .textFieldStyle(.plain)
                        .font(MisuraLook.font(20, .bold))
                        .frame(width: 90)
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(MisuraLook.card))
                        .boardEdge(9)
                        .onSubmit(saveWeight)
                }
                Spacer()
                if let avg = store.average(day) {
                    Text("avg ").foregroundStyle(MisuraBoard.ink) + Text(String(format: "%.1f", avg)).fontWeight(.bold).foregroundStyle(MisuraBoard.ink)
                }
            }
            .monospacedDigit()
        }
        .onChange(of: day) { editingWeight = false; weightText = "" }
    }

    private func saveWeight() {
        guard let kg = Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) else { return }
        store.weigh(kg, on: day)
        editingWeight = false
        weightText = ""
    }
}

private struct MisuraWeekView: View {
    @ObservedObject var store: MisuraStore
    @Binding var day: String
    let pick: (String) -> Void

    var body: some View {
        let days = MisuraDays.week(day)
        if let week = store.week(day) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { day = MisuraDays.shift(day, by: -7) } label: { Image(systemName: "chevron.left").foregroundStyle(MisuraBoard.muted).frame(width: 28, height: 28) }
                        .buttonStyle(.plain)
                    Text("\(MisuraDays.format(days[0], "MMMd")) – \(MisuraDays.format(days[6], "MMMd"))").font(MisuraLook.font(24, .bold)).foregroundStyle(MisuraBoard.ink)
                    Button { day = MisuraDays.shift(day, by: 7) } label: { Image(systemName: "chevron.right").foregroundStyle(MisuraBoard.muted).frame(width: 28, height: 28) }
                        .buttonStyle(.plain)
                    Spacer()
                    if week.due > 0 {
                        Text(week.underLimit ? "Under the limit" : "Over the limit")
                            .font(MisuraLook.font(11.5, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(week.underLimit ? MisuraBoard.under : MisuraBoard.over))
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    chart(week)
                        .frame(maxWidth: .infinity)
                    MisuraCard {
                        MisuraLook.kicker("Deficit")
                        HStack(alignment: .firstTextBaseline) {
                            Text(MisuraText.kcal(week.deficit)).font(MisuraLook.font(32, .bold)).foregroundStyle(MisuraBoard.ink)
                            Spacer()
                            Text("/ \(MisuraText.kcal(week.goal))").font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
                        }
                        MisuraBar(value: week.deficit / max(1, week.goal), marker: week.due / max(1, week.goal), height: 10)
                        row("Per day left", MisuraText.kcal(store.perDayLeft(week)))
                        row("Avg eaten", MisuraText.kcal(week.avgEaten))
                        row("Workouts", MisuraText.kcal(week.workouts))
                        if let first = store.average(MisuraDays.shift(days[0], by: -1)), let last = store.average(min(days[6], store.today)) {
                            row("Weight", "\(String(format: "%.1f", first)) → \(String(format: "%.1f", last))")
                        }
                    }
                    .monospacedDigit()
                    .frame(width: 300)
                }
                if week.days.contains(where: { $0.logged || store.weight(on: $0.day) != nil }) {
                    table(week)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(MisuraBoard.ink); Spacer(); Text(value).fontWeight(.bold).foregroundStyle(MisuraBoard.ink) }
            .font(MisuraLook.font(13))
    }

    private func chart(_ week: MisuraSpan) -> some View {
        let top = max(week.days.map { max($0.eaten, $0.budget) }.max() ?? 1, 1) * 1.08
        let height: CGFloat = 180
        return MisuraCard {
            MisuraLook.kicker("Eaten · workout")
            ZStack(alignment: .topLeading) {
                if let budget = week.days.first?.budget {
                    let y = 21 + height - height * budget / top
                    Rectangle().stroke(MisuraBoard.ink, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])).frame(height: 1)
                        .offset(y: y)
                    HStack {
                        Spacer()
                        Text(MisuraText.kcal(budget)).font(MisuraLook.font(11, .semibold)).foregroundStyle(MisuraBoard.ink)
                    }
                    .offset(y: y - 16)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(week.days, id: \.day) { summary in
                        Button { pick(summary.day) } label: {
                            VStack(spacing: 6) {
                                Text(summary.logged ? MisuraText.kcal(summary.eaten) : " ")
                                    .font(MisuraLook.font(11, .semibold))
                                    .foregroundStyle(summary.over ? MisuraBoard.overInk : MisuraBoard.ink)
                                    .frame(height: 15)
                                HStack(alignment: .bottom, spacing: 4) {
                                    if summary.logged {
                                        UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                                            .fill(summary.over ? MisuraBoard.over : MisuraBoard.under)
                                            .frame(width: 30, height: max(4, height * summary.eaten / top))
                                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).stroke(summary.day == store.today ? MisuraBoard.ink : .clear, lineWidth: 2).padding(-2))
                                        UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                                            .fill(MisuraBoard.burn)
                                            .frame(width: 12, height: height * summary.workout / top)
                                    } else {
                                        Capsule().fill(MisuraBoard.line).frame(width: 30, height: 4)
                                    }
                                }
                                .frame(height: height, alignment: .bottom)
                                Text(MisuraDays.weekdayShort(summary.day))
                                    .font(MisuraLook.font(11.5, summary.day == store.today ? .bold : .regular))
                                    .foregroundStyle(summary.day == store.today ? MisuraBoard.ink : MisuraBoard.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .monospacedDigit()
        }
    }

    private func table(_ week: MisuraSpan) -> some View {
        MisuraCard(padding: 10) {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow {
                    head("Day").gridColumnAlignment(.leading)
                    head("kg").gridColumnAlignment(.leading)
                    head("Eaten")
                    head("Workout")
                    head("BMR")
                    head("Deficit / goal")
                }
                .padding(.bottom, 6)
                ForEach(week.days.filter { $0.logged || store.weight(on: $0.day) != nil }, id: \.day) { summary in
                    Divider().overlay(MisuraBoard.line)
                    GridRow {
                        Text("\(MisuraDays.weekdayShort(summary.day)) \(MisuraDays.dayNumber(summary.day))")
                            .fontWeight(summary.day == store.today ? .bold : .regular)
                            .foregroundStyle(MisuraBoard.ink)
                        Group {
                            if let kg = store.weight(on: summary.day) {
                                Text(String(format: "%.1f", kg))
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(MisuraLook.card))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(MisuraBoard.line, lineWidth: 1.5))
                            } else {
                                Text("–").foregroundStyle(MisuraBoard.muted)
                            }
                        }
                        .foregroundStyle(MisuraBoard.ink)
                        Text(MisuraText.kcal(summary.eaten)).foregroundStyle(MisuraBoard.food)
                        Text(MisuraText.kcal(summary.workout)).foregroundStyle(MisuraBoard.under)
                        Text(MisuraText.kcal(summary.base)).foregroundStyle(MisuraBoard.under)
                        HStack(spacing: 3) {
                            Text(MisuraText.kcal(summary.deficit)).fontWeight(.bold)
                                .foregroundStyle(summary.deficit >= week.goal / Double(max(1, week.days.count)) ? MisuraBoard.under : MisuraBoard.overInk)
                            Text("/ \(MisuraText.kcal(MisuraMath.dailyGoal(store.plan!)))").font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .font(MisuraLook.font(13))
            .monospacedDigit()
        }
    }

    private func head(_ text: String) -> some View {
        Text(text.uppercased()).font(MisuraLook.font(10.5, .semibold)).tracking(1).foregroundStyle(MisuraBoard.muted)
    }
}

private struct MisuraMonthView: View {
    @ObservedObject var store: MisuraStore
    @Binding var day: String
    let pick: (String) -> Void

    var body: some View {
        let days = MisuraDays.monthDays(day)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { day = MisuraDays.monthShift(day, by: -1) } label: { Image(systemName: "chevron.left").foregroundStyle(MisuraBoard.muted).frame(width: 28, height: 28) }
                    .buttonStyle(.plain)
                Text(MisuraDays.month(day)).font(MisuraLook.font(24, .bold)).foregroundStyle(MisuraBoard.ink)
                Button { day = MisuraDays.monthShift(day, by: 1) } label: { Image(systemName: "chevron.right").foregroundStyle(MisuraBoard.muted).frame(width: 28, height: 28) }
                    .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 14) {
                calendar(days)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    if let loss = store.monthLoss(day), let span = store.month(day) {
                        MisuraCard {
                            MisuraLook.kicker("Weight")
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(MisuraText.kg(-loss.lost)) kg").font(MisuraLook.font(26, .bold)).foregroundStyle(MisuraBoard.ink)
                                Spacer()
                                Text("/ \(MisuraText.kg(-loss.target))").font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
                            }
                            MisuraBar(value: loss.lost / max(0.1, loss.target), marker: loss.due / max(0.1, loss.target))
                            HStack { Text("Deficit"); Spacer(); Text("\(MisuraText.kcal(span.deficit)) / \(MisuraText.kcal(span.goal))").fontWeight(.bold) }
                            HStack { Text("Avg eaten"); Spacer(); Text(MisuraText.kcal(span.avgEaten)).fontWeight(.bold) }
                        }
                        .foregroundStyle(MisuraBoard.ink)
                        .monospacedDigit()
                    }
                    MisuraCard {
                        MisuraLook.kicker("Trend")
                        MisuraTrend(store: store, days: days.filter { $0 <= store.today })
                            .frame(height: 220)
                    }
                }
                .frame(width: 380)
            }
        }
    }

    private func calendar(_ days: [String]) -> some View {
        let lead = (MisuraDays.weekday(days[0]) + 5) % 7
        let cells: [String?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        return MisuraCard {
            MisuraLook.kicker("Eaten")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(MisuraDays.week(days[0]), id: \.self) { key in
                    Text(MisuraDays.weekdayShort(key)).font(MisuraLook.font(10.5, .semibold)).foregroundStyle(MisuraBoard.muted)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, key in
                    if let key {
                        cell(key)
                    } else {
                        Color.clear.frame(height: 62)
                    }
                }
            }
        }
    }

    private func cell(_ key: String) -> some View {
        let summary = store.summary(key)
        let logged = summary?.logged == true
        let fill = !logged ? MisuraBoard.line.opacity(0.6) : (summary?.over == true ? MisuraBoard.over : MisuraBoard.under)
        return Button { pick(key) } label: {
            VStack(alignment: .leading) {
                Text("\(MisuraDays.dayNumber(key))").font(MisuraLook.font(12, .bold))
                Spacer()
                if logged, let summary { Text(MisuraText.kcal(summary.eaten)).font(MisuraLook.font(11)).opacity(0.92) }
            }
            .foregroundStyle(logged ? Color.white : MisuraBoard.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(key == store.today ? MisuraBoard.ink : .clear, lineWidth: 2).padding(-2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .monospacedDigit()
    }
}

struct MisuraTrend: View {
    @ObservedObject var store: MisuraStore
    let days: [String]

    var body: some View {
        let points = days.compactMap { key -> (Int, Double, Double)? in
            guard let kg = store.weight(on: key), let avg = store.average(key), let index = days.firstIndex(of: key) else { return nil }
            return (index, kg, avg)
        }
        GeometryReader { geo in
            if points.isEmpty {
                Text("No weigh-ins yet").font(MisuraLook.font(12)).foregroundStyle(MisuraBoard.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let values = points.flatMap { [$0.1, $0.2] }
                let low = (values.min() ?? 0) - 0.4
                let high = (values.max() ?? 1) + 0.4
                let width = geo.size.width - 30
                let height = geo.size.height - 20
                let step = width / CGFloat(max(1, days.count - 1))
                let y: (Double) -> CGFloat = { CGFloat((high - $0) / max(0.1, high - low)) * height }
                ZStack(alignment: .topLeading) {
                    ForEach([high - 0.4, (high + low) / 2, low + 0.4], id: \.self) { mark in
                        Rectangle().fill(MisuraBoard.line.opacity(0.6)).frame(width: width, height: 1).offset(x: 30, y: y(mark))
                        Text(String(format: "%.0f", mark)).font(MisuraLook.font(11)).foregroundStyle(MisuraBoard.muted).offset(x: 0, y: y(mark) - 8)
                    }
                    ForEach(points, id: \.0) { point in
                        Circle().fill(MisuraBoard.faint).frame(width: 6, height: 6).offset(x: 30 + CGFloat(point.0) * step - 3, y: y(point.1) - 3)
                    }
                    Path { path in
                        for (n, point) in points.enumerated() {
                            let p = CGPoint(x: 30 + CGFloat(point.0) * step, y: y(point.2))
                            if n == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                    }
                    .stroke(MisuraBoard.accentInk, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    if let last = points.last {
                        Circle().fill(MisuraBoard.accentInk).frame(width: 12, height: 12).overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 30 + CGFloat(last.0) * step - 6, y: y(last.2) - 6)
                    }
                    HStack {
                        Text(MisuraDays.short(days.first ?? ""))
                        Spacer()
                        Text(MisuraDays.short(days.last ?? ""))
                    }
                    .font(MisuraLook.font(11))
                    .foregroundStyle(MisuraBoard.muted)
                    .frame(width: width)
                    .offset(x: 30, y: height + 4)
                }
            }
        }
    }
}

private struct MisuraSetup: View {
    @ObservedObject var store: MisuraStore
    @State private var draft = MisuraPlanDraft()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your plan").font(MisuraLook.font(28, .bold)).foregroundStyle(MisuraBoard.ink)
                MisuraPlanFields(draft: $draft)
                if let plan = draft.plan {
                    MisuraCard {
                        HStack { Text("Daily deficit"); Spacer(); Text(MisuraText.kcal(MisuraMath.dailyGoal(plan))).fontWeight(.bold) }
                        HStack { Text("Burn"); Spacer(); Text(MisuraText.kcal(MisuraMath.base(plan, kg: plan.startKg, on: plan.startDay))).fontWeight(.bold) }
                        HStack { Text("Budget"); Spacer(); Text(MisuraText.kcal(MisuraMath.budget(plan, base: MisuraMath.base(plan, kg: plan.startKg, on: plan.startDay)))).fontWeight(.bold) }
                    }
                    .foregroundStyle(MisuraBoard.ink)
                    .monospacedDigit()
                }
                Button {
                    if let plan = draft.plan { store.setPlan(plan) }
                } label: {
                    Text("Start")
                        .font(MisuraLook.font(15, .semibold))
                        .foregroundStyle(MisuraLook.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(MisuraBoard.accentInk))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(draft.plan == nil)
                .opacity(draft.plan == nil ? 0.4 : 1)
            }
            .frame(maxWidth: 440)
            .padding(.vertical, 50)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

struct MisuraPlanDraft {
    var born = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    var sex = "male"
    var height = ""
    var activity = 1.2
    var startKg = ""
    var startDay = Date()
    var goalKg = ""
    var goalDay = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    var pace = "fastest"
    var floor = "1500"

    init() {}

    init(_ plan: MisuraPlan) {
        born = MisuraDays.date(plan.born) ?? born
        sex = plan.sex
        height = MisuraPlanDraft.number(plan.heightCm)
        activity = plan.activity
        startKg = MisuraPlanDraft.number(plan.startKg)
        startDay = MisuraDays.date(plan.startDay) ?? startDay
        goalKg = MisuraPlanDraft.number(plan.goalKg)
        goalDay = MisuraDays.date(plan.goalDay) ?? goalDay
        pace = plan.pace
        floor = MisuraPlanDraft.number(plan.floor)
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func read(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    var plan: MisuraPlan? {
        guard let h = Self.read(height), h > 100, h < 250,
              let start = Self.read(startKg), start > 25, start < 400,
              let goal = Self.read(goalKg), goal > 25, goal < 400,
              let low = Self.read(floor), low >= 800, low <= 5000 else { return nil }
        let first = MisuraDays.key(startDay)
        let last = MisuraDays.key(goalDay)
        guard last > first else { return nil }
        var plan = MisuraPlan(born: MisuraDays.key(born), sex: sex, heightCm: h, activity: activity, startDay: first, startKg: start, goalKg: goal, goalDay: last)
        plan.pace = pace
        plan.floor = low
        return plan
    }
}

struct MisuraPlanFields: View {
    @Binding var draft: MisuraPlanDraft
    var compact = false

    static let activities: [(String, Double)] = [("Sitting", 1.2), ("Light", 1.375), ("Moderate", 1.55), ("Active", 1.725)]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                field("Born") { DatePicker("", selection: $draft.born, displayedComponents: .date).labelsHidden().datePickerStyle(.field) }
                field("Sex") {
                    Picker("", selection: $draft.sex) { Text("Male").tag("male"); Text("Female").tag("female") }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                field("Height") { number($draft.height, unit: "cm") }
                field("Activity") {
                    Picker("", selection: $draft.activity) { ForEach(Self.activities, id: \.1) { Text($0.0).tag($0.1) } }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                field("Weight") { number($draft.startKg, unit: "kg") }
                field("From") { DatePicker("", selection: $draft.startDay, displayedComponents: .date).labelsHidden().datePickerStyle(.field) }
                field("Goal") { number($draft.goalKg, unit: "kg") }
                field("By") { DatePicker("", selection: $draft.goalDay, displayedComponents: .date).labelsHidden().datePickerStyle(.field) }
            }
            HStack {
                Text("Pace").foregroundStyle(MisuraBoard.ink)
                Spacer()
                MisuraSegment(options: [("Fastest", "fastest"), ("On time", "ontime")], selection: $draft.pace, compact: true)
            }
            HStack {
                Text("Lowest budget").foregroundStyle(MisuraBoard.ink)
                Spacer()
                number($draft.floor, unit: "kcal").frame(width: 110)
            }
        }
        .font(MisuraLook.font(compact ? 12.5 : 13))
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title).font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
            Spacer(minLength: 2)
            content()
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(MisuraLook.card))
        .boardEdge(8)
    }

    private func number(_ text: Binding<String>, unit: String) -> some View {
        HStack(spacing: 3) {
            TextField("", text: text).textFieldStyle(.plain).multilineTextAlignment(.trailing).fontWeight(.bold)
            Text(unit).font(MisuraLook.font(11)).foregroundStyle(MisuraBoard.muted)
        }
        .foregroundStyle(MisuraBoard.ink)
    }
}

private struct MisuraSettings: View {
    @ObservedObject var store: MisuraStore
    @ObservedObject var vault = DataVault.shared
    @State private var draft = MisuraPlanDraft()
    @State private var loaded = false
    @State private var reminder = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(MisuraLook.font(15, .bold)).foregroundStyle(MisuraBoard.ink).padding(.top, 34)
                if let plan = store.plan {
                    VStack(alignment: .leading, spacing: 8) {
                        MisuraLook.kicker("Plan")
                        MisuraPlanFields(draft: $draft, compact: true)
                        HStack {
                            Text("Budget").foregroundStyle(MisuraBoard.ink)
                            Spacer()
                            Text(MisuraText.kcal(store.summary(store.today)?.budget ?? plan.floor)).fontWeight(.bold).foregroundStyle(MisuraBoard.ink)
                        }
                        HStack {
                            Text("Daily deficit").foregroundStyle(MisuraBoard.ink)
                            Spacer()
                            Text(MisuraText.kcal(MisuraMath.dailyGoal(draft.plan ?? plan))).fontWeight(.bold).foregroundStyle(MisuraBoard.ink)
                        }
                        if let next = draft.plan, next != withExtras(next, plan) {
                            Button {
                                store.setPlan(withExtras(next, plan))
                            } label: {
                                Text("Save plan").font(MisuraLook.font(12.5, .semibold)).foregroundStyle(MisuraLook.onAccent)
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(MisuraBoard.accentInk))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .monospacedDigit()
                    VStack(alignment: .leading, spacing: 8) {
                        MisuraLook.kicker("Workouts")
                        HStack {
                            Text("Watch counts").foregroundStyle(MisuraBoard.ink)
                            Spacer()
                            Stepper(value: Binding(get: { plan.watchShare * 100 }, set: { value in store.editPlan { $0.watchShare = value / 100 } }), in: 0...100, step: 5) {
                                Text("\(Int((plan.watchShare * 100).rounded()))%").fontWeight(.bold).foregroundStyle(MisuraBoard.ink)
                            }
                        }
                        Toggle("Eat back", isOn: Binding(get: { plan.eatBack }, set: { value in store.editPlan { $0.eatBack = value } }))
                            .toggleStyle(.switch).tint(MisuraBoard.accentInk)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MisuraLook.kicker("Menu bar")
                        Toggle("Show kcal left", isOn: Binding(get: { plan.menuLeft }, set: { value in
                            store.editPlan { $0.menuLeft = value }
                            AppDelegate.shared.apps["calorie"]?.changed()
                        }))
                        .toggleStyle(.switch).tint(MisuraBoard.accentInk)
                        Toggle("Weigh-in reminder", isOn: Binding(get: { plan.weighAt != nil }, set: { value in
                            store.editPlan { $0.weighAt = value ? (plan.weighAt ?? "07:00") : nil }
                        }))
                        .toggleStyle(.switch).tint(MisuraBoard.accentInk)
                        if plan.weighAt != nil {
                            DatePicker("At", selection: Binding(get: { reminder }, set: { value in
                                reminder = value
                                let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                                store.editPlan { $0.weighAt = String(format: "%02d:%02d", parts.hour ?? 7, parts.minute ?? 0) }
                            }), displayedComponents: .hourAndMinute)
                            .datePickerStyle(.field)
                        }
                    }
                    .foregroundStyle(MisuraBoard.ink)
                    backup
                }
            }
            .font(MisuraLook.font(13))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .onAppear(perform: load)
        .onChange(of: store.plan) { load() }
    }

    private func load() {
        guard let plan = store.plan else { return }
        draft = MisuraPlanDraft(plan)
        if let (hour, minute) = plan.weighAt.flatMap(MisuraReminder.parse) {
            reminder = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
    }

    private func withExtras(_ next: MisuraPlan, _ plan: MisuraPlan) -> MisuraPlan {
        var merged = next
        merged.watchShare = plan.watchShare
        merged.eatBack = plan.eatBack
        merged.menuLeft = plan.menuLeft
        merged.weighAt = plan.weighAt
        return merged
    }

    private var backup: some View {
        VStack(alignment: .leading, spacing: 8) {
            MisuraLook.kicker("Backup")
            if let last = vault.lastSync {
                Text("Synced \(last.formatted(date: .omitted, time: .shortened))").font(MisuraLook.font(11.5)).foregroundStyle(MisuraBoard.muted)
            }
            HStack(spacing: 8) {
                Menu {
                    let snaps = store.snapshots()
                    if snaps.isEmpty { Text("No daily copies yet") }
                    ForEach(snaps, id: \.snapshot.id) { entry in
                        Button("\(entry.snapshot.day.formatted(date: .abbreviated, time: .omitted)) · \(entry.entries) logs") { confirm(entry.snapshot) }
                    }
                } label: {
                    Text("Restore…").font(MisuraLook.font(12, .medium)).foregroundStyle(MisuraBoard.ink)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Button("Show backups") { vault.showInFinder() }
                    .buttonStyle(.plain)
                    .font(MisuraLook.font(12, .medium))
                    .foregroundStyle(MisuraBoard.muted)
            }
        }
    }

    private func confirm(_ snap: VaultSnapshot) {
        let alert = NSAlert()
        alert.messageText = "Restore Terra from \(snap.day.formatted(date: .long, time: .omitted))?"
        alert.informativeText = "Today's copy is kept as its own backup first, so this can be undone."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.restore(snap)
    }
}
