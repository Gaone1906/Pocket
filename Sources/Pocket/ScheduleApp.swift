import AppKit
import Combine
import SwiftUI

final class ScheduleApp: PocketApp {
    private var watch: AnyCancellable?
    private var themeWatch: AnyCancellable?
    private var badge: Int?

    override init(spec: AppSpec) {
        super.init(spec: spec)
    }

    override var defaultSize: NSSize { NSSize(width: 380, height: 560) }
    override var minSize: NSSize { NSSize(width: 380, height: 560) }
    override var resizable: Bool { false }

    override func start() {
        let store = ScheduleStore.shared
        watch = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
        note("schedule app started routines=\(store.routines.count) day=\(store.today) slot=\(store.slotNow.rawValue) left=\(badge ?? 0)")
    }

    private var remaining: Int {
        let store = ScheduleStore.shared
        return store.items(on: store.today, slot: store.slotNow).filter { !$0.done }.count
    }

    private func refresh() {
        let count = remaining
        guard count != badge else { return }
        badge = count
        changed()
    }

    override func makeContent() -> NSView {
        let view = ScheduleDropdown(store: ScheduleStore.shared) { [weak self] in self?.openBoard(source: "dropdown") }
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = BoardThemeStore.shared.theme.appearance
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak hosting] theme in hosting?.appearance = theme.appearance }
        return hosting
    }

    override func didShow() {
        ScheduleStore.shared.tick()
    }

    override func barImage() -> NSImage? {
        AppIcon.render(spec, unread: badge ?? remaining)
    }

    override func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "Open schedule", action: #selector(openFromMenu), keyEquivalent: "")
        item.target = self
        return [item]
    }

    @objc private func openFromMenu() {
        openBoard(source: "menu")
    }

    private func openBoard(source: String) {
        let store = ScheduleStore.shared
        hide(reason: "switched")
        note("schedule board requested source=\(source) day=\(store.today) filter=\(store.filterName)")
        ScheduleBoardWindow.shared.present()
    }
}

private enum ScheduleLook {
    static let dateFormat: DateFormatter = {
        let format = DateFormatter()
        format.calendar = ScheduleDays.calendar
        format.timeZone = ScheduleDays.calendar.timeZone
        format.locale = .current
        format.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return format
    }()

    static var chip: Color { Board.line.opacity(0.55) }

    static func title(_ day: String) -> String {
        ScheduleDays.date(day).map(dateFormat.string(from:)) ?? day
    }

    static func heading(_ slot: ScheduleSlot) -> String { slot == .morning ? "This morning" : "Tonight" }

    static func dot(_ color: Color) -> NSImage {
        let fill = NSColor(color)
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct ScheduleDropdown: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var themes = BoardThemeStore.shared
    let openBoard: () -> Void
    @State private var tips: Set<String> = []
    @State private var otherOpen = false

    var body: some View {
        VStack(spacing: 0) {
            ScheduleHeader(store: store, openBoard: openBoard)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 14)
            Rectangle().fill(Board.line).frame(height: 1)
            if store.routines.isEmpty {
                ScheduleNoRoutines(openBoard: openBoard)
            } else {
                content
            }
        }
        .animation(Board.glide, value: otherOpen)
        .animation(Board.glide, value: tips)
        .id(themes.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardBackdrop(theme: themes.theme))
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
    }

    private var content: some View {
        let day = store.today
        let slot = store.slotNow
        let other: ScheduleSlot = slot == .morning ? .night : .morning
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if other == .morning { fold(other, day: day) }
                    ScheduleSlotCard(store: store, day: day, slot: slot, tips: $tips)
                    if other == .night { fold(other, day: day) }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
            ScheduleTallyLine(store: store)
                .padding(.bottom, 14)
                .padding(.top, 6)
        }
    }

    private func fold(_ slot: ScheduleSlot, day: String) -> some View {
        ScheduleFold(store: store, day: day, slot: slot, open: $otherOpen, tips: $tips)
    }
}

private struct ScheduleHeader: View {
    @ObservedObject var store: ScheduleStore
    let openBoard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ScheduleLook.title(store.today))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    Image(systemName: store.slotNow.symbol)
                    Text(store.slotNow.label)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Board.accentInkStyle)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Board.accent.opacity(0.14)))
            }
            Spacer(minLength: 8)
            if !store.routines.isEmpty {
                ScheduleFilterMenu(store: store)
            }
            Button(action: openBoard) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Board.muted)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(ScheduleLook.chip))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open the schedule board in its own window")
        }
    }
}

private struct ScheduleFilterMenu: View {
    @ObservedObject var store: ScheduleStore

    private var tint: Color {
        store.filter.flatMap(store.routine).map { Board.hue($0.hue) } ?? Board.muted
    }

    var body: some View {
        Menu {
            Picker("Routine", selection: $store.filter) {
                Text("All routines").tag(UUID?.none)
                ForEach(store.routines) { routine in
                    Label {
                        Text(routine.name)
                    } icon: {
                        Image(nsImage: ScheduleLook.dot(Board.hue(routine.hue)))
                    }
                    .tag(UUID?.some(routine.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(store.filterName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Board.muted)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: 140)
            .background(Capsule().fill(ScheduleLook.chip))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Show one routine or all of them")
    }
}

private struct ScheduleSlotCard: View {
    @ObservedObject var store: ScheduleStore
    let day: String
    let slot: ScheduleSlot
    @Binding var tips: Set<String>

    var body: some View {
        let items = store.items(on: day, slot: slot)
        let done = items.filter(\.done).count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(ScheduleLook.heading(slot).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Board.muted)
                Spacer()
                if !items.isEmpty {
                    Text("\(done) of \(items.count) done")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Board.muted)
                        .contentTransition(.numericText())
                }
            }
            if items.isEmpty {
                ScheduleQuietSlot(slot: slot)
            } else {
                ScheduleProgress(done: done, total: items.count)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                ScheduleChecklist(store: store, items: items, tips: $tips)
                ScheduleMarkAll(store: store, day: day, slot: slot, finished: done == items.count)
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
        .boardEdge(16)
        .shadow(color: Board.shadow, radius: 10, y: 3)
    }
}

private struct ScheduleFold: View {
    @ObservedObject var store: ScheduleStore
    let day: String
    let slot: ScheduleSlot
    @Binding var open: Bool
    @Binding var tips: Set<String>

    var body: some View {
        let items = store.items(on: day, slot: slot)
        let done = items.filter(\.done).count
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !items.isEmpty else { return }
                open.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: slot.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Board.muted)
                        .frame(width: 16)
                    Text(slot.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Board.ink)
                    Text("· " + summary(done: done, total: items.count))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Board.muted)
                    Spacer(minLength: 6)
                    if !items.isEmpty && done == items.count {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Board.accentInkStyle)
                    }
                    if !items.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Board.faint)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(items.isEmpty ? "" : open ? "Hide these steps" : "Show these steps")
            if open && !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ScheduleChecklist(store: store, items: items, tips: $tips)
                    ScheduleMarkAll(store: store, day: day, slot: slot, finished: done == items.count)
                        .padding(.top, 6)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Board.column.opacity(0.6)))
        .boardEdge(14)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func summary(done: Int, total: Int) -> String {
        if total == 0 { return "nothing planned" }
        if done == 0 { return total == 1 ? "1 step" : "\(total) steps" }
        return "\(done) of \(total) done"
    }
}

private struct ScheduleChecklist: View {
    @ObservedObject var store: ScheduleStore
    let items: [ScheduleItem]
    @Binding var tips: Set<String>

    var body: some View {
        let tagged = store.filter == nil && store.routines.count > 1
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                ScheduleRow(
                    item: item,
                    tagged: tagged,
                    tipOpen: tips.contains(item.id),
                    toggle: { withAnimation(Board.glide) { store.toggle(item) } },
                    flip: {
                        if tips.contains(item.id) { tips.remove(item.id) } else { tips.insert(item.id) }
                    }
                )
            }
        }
    }
}

private struct ScheduleRow: View {
    let item: ScheduleItem
    let tagged: Bool
    let tipOpen: Bool
    let toggle: () -> Void
    let flip: () -> Void

    private var tint: Color { tagged ? Board.hue(item.routine.hue) : Board.accent }
    private var tip: String { item.step.tip.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: toggle) {
                    ZStack {
                        Circle()
                            .strokeBorder(item.done ? Color.clear : Board.faint, lineWidth: 1.5)
                        if item.done {
                            Circle().fill(tagged ? AnyShapeStyle(tint) : Board.accentStyle)
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Board.theme.isDark ? Board.backdrop : .white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(item.done ? "Mark as not done" : "Mark as done")
                ScheduleStepText.make(item.step.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.done ? Board.muted : Board.ink)
                    .strikethrough(item.done, color: Board.faint)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggle)
                if tagged {
                    Text(item.routine.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.14)))
                        .fixedSize()
                }
                if !tip.isEmpty {
                    Button(action: flip) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tipOpen ? Board.ink : Board.faint)
                            .rotationEffect(.degrees(tipOpen ? 180 : 0))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tipOpen ? "Hide how to do it" : "How to do it")
                }
            }
            if tipOpen && !tip.isEmpty {
                Text(tip)
                    .font(.system(size: 12))
                    .foregroundStyle(Board.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.leading, 28)
                    .padding(.trailing, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 7)
        .opacity(item.done ? 0.62 : 1)
    }
}

private struct ScheduleProgress: View {
    let done: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Board.line.opacity(0.7))
                Capsule()
                    .fill(Board.accentStyle)
                    .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total))
            }
        }
        .frame(height: 3)
        .animation(Board.glide, value: done)
    }
}

private struct ScheduleMarkAll: View {
    @ObservedObject var store: ScheduleStore
    let day: String
    let slot: ScheduleSlot
    let finished: Bool

    var body: some View {
        HStack {
            Spacer()
            if finished {
                Label("All done", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Board.accentInkStyle)
            } else {
                Button("Mark all done") {
                    withAnimation(Board.glide) { store.setAll(on: day, slot: slot, done: true) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Board.accentInkStyle)
            }
        }
    }
}

private struct ScheduleQuietSlot: View {
    let slot: ScheduleSlot

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: slot.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Board.faint)
                .padding(.bottom, 4)
            Text(slot == .morning ? "Nothing this morning" : "Nothing tonight")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Board.ink)
            Text(slot == .morning ? "A free start to the day. Take it slow." : "Nothing to do but rest.")
                .font(.system(size: 12))
                .foregroundStyle(Board.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

private struct ScheduleNoRoutines: View {
    let openBoard: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "sun.horizon")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Board.faint)
                .padding(.bottom, 4)
            Text("No routines yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Board.ink)
            Text("Plan a week of mornings and nights on the board.")
                .font(.system(size: 12))
                .foregroundStyle(Board.muted)
                .multilineTextAlignment(.center)
            Button(action: openBoard) {
                Text("Open the board")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Board.theme.isDark ? Board.backdrop : .white)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(Capsule().fill(Board.accentStyle))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScheduleTallyLine: View {
    @ObservedObject var store: ScheduleStore

    var body: some View {
        let tally = store.tally()
        let missed = tally.missed + tally.partial
        Text("\(tally.done) \(tally.done == 1 ? "day" : "days") done · \(missed) missed since \(Self.start(store.firstDay))")
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Board.muted)
            .frame(maxWidth: .infinity)
    }

    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f
    }()

    private static func start(_ key: String) -> String { ScheduleDays.date(key).map(format.string) ?? key }
}
