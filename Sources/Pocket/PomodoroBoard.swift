import AppKit
import SwiftUI

struct PomodoroProject: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var hue: Int
}

struct PomodoroSession: Codable, Identifiable, Equatable {
    let id: UUID
    let ended: Date
    let minutes: Int
    var project: UUID?
}

final class PomodoroBoardStore: ObservableObject {
    static let shared = PomodoroBoardStore()

    @Published private(set) var projects: [PomodoroProject] = []
    @Published private(set) var sessions: [PomodoroSession] = []
    private let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Pocket/Pomodoro/board.json")

    private struct Saved: Codable {
        var projects: [PomodoroProject]
        var sessions: [PomodoroSession]
    }

    private init() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
            projects = saved.projects
            sessions = saved.sessions
            note("pomodoro board loaded projects=\(projects.count) sessions=\(sessions.count)")
        } catch {
            note("pomodoro board load failed path=\(file.path) error=\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(projects: projects, sessions: sessions)).write(to: file, options: .atomic)
        } catch {
            note("pomodoro board save failed projects=\(projects.count) sessions=\(sessions.count) error=\(error.localizedDescription)")
        }
    }

    func sessions(in project: UUID?) -> [PomodoroSession] {
        sessions.filter { $0.project == project }
    }

    func project(_ id: UUID?) -> PomodoroProject? {
        projects.first { $0.id == id }
    }

    func record(minutes: Int, ended: Date, project: UUID? = nil) {
        let session = PomodoroSession(id: UUID(), ended: ended, minutes: minutes, project: project)
        sessions.append(session)
        save()
        note("pomodoro session recorded session=\(session.id) minutes=\(minutes) project=\(project?.uuidString ?? "unassigned") total=\(sessions.count)")
    }

    func projectId(named name: String) -> UUID {
        if let found = projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return found.id }
        let id = addProject()
        rename(id, name)
        return id
    }

    func assign(_ id: UUID, to project: UUID?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].project != project else { return }
        let from = sessions[index].project
        sessions[index].project = project
        save()
        note("pomodoro session assigned session=\(id) from=\(from?.uuidString ?? "unassigned") to=\(project?.uuidString ?? "unassigned")")
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
        note("pomodoro session deleted session=\(id) remaining=\(sessions.count)")
    }

    @discardableResult
    func addProject() -> UUID {
        let used = Set(projects.map(\.hue))
        let hue = (0..<Board.hues.count).first { !used.contains($0) } ?? projects.count % Board.hues.count
        let project = PomodoroProject(id: UUID(), name: "", hue: hue)
        projects.append(project)
        save()
        note("pomodoro project created project=\(project.id) total=\(projects.count)")
        return project.id
    }

    func rename(_ id: UUID, _ name: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }), projects[index].name != name else { return }
        projects[index].name = name
        save()
        note("pomodoro project renamed project=\(id) name=\(name)")
    }

    func deleteProject(_ id: UUID) {
        let moved = sessions.indices.filter { sessions[$0].project == id }
        moved.forEach { sessions[$0].project = nil }
        projects.removeAll { $0.id == id }
        save()
        note("pomodoro project deleted project=\(id) sessionsUnassigned=\(moved.count)")
    }
}

enum Board {
    static let backdrop = Color(red: 0.071, green: 0.075, blue: 0.082)
    static let sidebar = Color(red: 0.094, green: 0.098, blue: 0.106)
    static let column = Color(red: 0.118, green: 0.122, blue: 0.133)
    static let line = Color.white.opacity(0.07)
    static let muted = Color(red: 0.545, green: 0.557, blue: 0.580)
    static let ink = Color.white.opacity(0.9)
    static let gold = Color(nsColor: PomodoroPalette.gold)
    static let hues: [Color] = [
        Color(red: 0.47, green: 0.78, blue: 0.67),
        Color(red: 0.55, green: 0.69, blue: 0.95),
        Color(red: 0.93, green: 0.55, blue: 0.48),
        Color(red: 0.74, green: 0.60, blue: 0.93),
        Color(red: 0.62, green: 0.82, blue: 0.43),
        Color(red: 0.93, green: 0.62, blue: 0.80),
        Color(red: 0.45, green: 0.80, blue: 0.88),
        Color(red: 0.90, green: 0.76, blue: 0.35),
    ]

    static func hue(_ index: Int) -> Color { hues[((index % hues.count) + hues.count) % hues.count] }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

enum SessionMenu {
    static func show(_ session: PomodoroSession, store: PomodoroBoardStore) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "\(session.minutes) min · \(session.ended.formatted(.dateTime.day().month(.abbreviated).hour().minute()))", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item("Unassigned", on: session.project == nil) { store.assign(session.id, to: nil) })
        for project in store.projects {
            menu.addItem(item(project.name.isEmpty ? "Untitled" : project.name, on: session.project == project.id) { store.assign(session.id, to: project.id) })
        }
        menu.addItem(.separator())
        menu.addItem(item("Delete session", on: false) { store.deleteSession(session.id) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func item(_ title: String, on: Bool, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.state = on ? .on : .off
        return item
    }
}

private struct GlowDot: View {
    @State private var bright = false

    var body: some View {
        Circle()
            .fill(Board.gold)
            .frame(width: 10, height: 10)
            .shadow(color: Board.gold.opacity(bright ? 0.95 : 0.55), radius: bright ? 7 : 4)
            .shadow(color: Board.gold.opacity(0.35), radius: 12)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}

struct TallyStick: Identifiable {
    static let fullMinutes = 25

    let session: PomodoroSession
    let index: Int
    let fraction: CGFloat

    var id: String { "\(session.id.uuidString)-\(index)" }

    static func sticks(for sessions: [PomodoroSession]) -> [TallyStick] {
        sessions.flatMap { session -> [TallyStick] in
            let minutes = max(1, session.minutes)
            let full = minutes / fullMinutes
            let rest = minutes % fullMinutes
            var sticks = (0..<full).map { TallyStick(session: session, index: $0, fraction: 1) }
            if rest > 0 { sticks.append(TallyStick(session: session, index: full, fraction: CGFloat(rest) / CGFloat(fullMinutes))) }
            return sticks
        }
    }
}

private struct TallyGroup: View {
    let sticks: [TallyStick]
    let tint: Color
    let tap: (PomodoroSession) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(sticks.prefix(4)) { stick in
                    mark(stick, length: 34)
                }
            }
            .frame(height: 40, alignment: .bottom)
            if sticks.count == 5, let last = sticks.last {
                mark(last, length: 46)
                    .rotationEffect(.degrees(62))
                    .frame(width: 44, height: 40)
            }
        }
        .frame(width: 44, height: 40, alignment: .bottomLeading)
    }

    func mark(_ stick: TallyStick, length: CGFloat) -> some View {
        Capsule()
            .fill(tint.opacity(stick.fraction < 1 ? 0.75 : 1))
            .frame(width: 3, height: max(6, length * stick.fraction))
            .padding(.horizontal, 4)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
            .onTapGesture { tap(stick.session) }
            .draggable(stick.session.id.uuidString)
            .help("\(stick.session.minutes) min · \(stick.session.ended.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
    }
}

private struct BoardColumn: View {
    let project: PomodoroProject?
    @ObservedObject var store: PomodoroBoardStore
    @State private var name = ""
    @State private var targeted = false
    @FocusState private var editing: Bool

    private var sessions: [PomodoroSession] { store.sessions(in: project?.id) }
    private var tint: Color { project.map { Board.hue($0.hue) } ?? Board.gold }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                if let project {
                    TextField("Project name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Board.ink)
                        .focused($editing)
                        .onSubmit { commit(project.id) }
                        .onChange(of: editing) { _, now in if !now { commit(project.id) } }
                } else {
                    Text("Unassigned")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Board.ink)
                }
                Spacer(minLength: 4)
                Text("\(sessions.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Board.muted)
                if let project {
                    Menu {
                        Button("Delete project", role: .destructive) { store.deleteProject(project.id) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(Board.muted)
                }
            }
            Text(sessions.isEmpty ? (project == nil ? "Finished sessions land here" : "Drag or click a session to assign it") : "\(Board.duration(sessions.reduce(0) { $0 + $1.minutes })) focused")
                .font(.system(size: 11))
                .foregroundStyle(Board.muted)
                .padding(.leading, 15)
            ScrollView(.vertical, showsIndicators: false) {
                if project == nil {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 22, maximum: 22), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(sessions) { session in
                            GlowDot()
                                .onTapGesture { SessionMenu.show(session, store: store) }
                                .draggable(session.id.uuidString)
                                .help(session.ended.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        }
                    }
                    .padding(.top, 14)
                } else {
                    let sticks = TallyStick.sticks(for: sessions)
                    let groups = stride(from: 0, to: sticks.count, by: 5).map { Array(sticks[$0..<min($0 + 5, sticks.count)]) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 20)], alignment: .leading, spacing: 16) {
                        ForEach(groups, id: \.first!.id) { group in
                            TallyGroup(sticks: group, tint: tint) { SessionMenu.show($0, store: store) }
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(targeted ? tint.opacity(0.8) : Board.line, lineWidth: targeted ? 1.5 : 1))
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(UUID.init(uuidString:))
            ids.forEach { store.assign($0, to: project?.id) }
            return !ids.isEmpty
        } isTargeted: { targeted = $0 }
        .onAppear {
            name = project?.name ?? ""
            if project != nil && name.isEmpty { editing = true }
        }
    }

    private func commit(_ id: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmed.isEmpty ? "Untitled" : trimmed
        store.rename(id, name)
    }
}

private struct SettingRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Board.muted)
            HStack(spacing: 10) {
                step("minus", -1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 20, weight: .bold).width(.condensed))
                        .monospacedDigit()
                        .foregroundStyle(Board.ink)
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Board.muted)
                }
                .frame(minWidth: 84)
                step("plus", 1)
            }
        }
    }

    private func step(_ symbol: String, _ delta: Int) -> some View {
        Button {
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Board.ink.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct BoardSettings: View {
    @ObservedObject var model: PomodoroModel
    @ObservedObject var store: PomodoroBoardStore

    private var today: [PomodoroSession] { store.sessions.filter { Calendar.current.isDateInToday($0.ended) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TIMER")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Board.muted)
            SettingRow(title: "Focus", value: $model.focusMinutes, range: 1...120, unit: "min")
            SettingRow(title: "Short break", value: $model.breakMinutes, range: 1...60, unit: "min")
            SettingRow(title: "Long break", value: $model.longBreakMinutes, range: 1...90, unit: "min")
            SettingRow(title: "Long break after", value: $model.longEvery, range: 2...12, unit: "sessions")
            Rectangle().fill(Board.line).frame(height: 1).padding(.vertical, 4)
            Text("TODAY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Board.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(today.count)")
                    .font(.system(size: 28, weight: .bold).width(.condensed))
                    .foregroundStyle(Board.gold)
                Text(today.count == 1 ? "session" : "sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(Board.muted)
            }
            Text("\(Board.duration(today.reduce(0) { $0 + $1.minutes })) focused · \(store.sessions.count) all time")
                .font(.system(size: 11))
                .foregroundStyle(Board.muted)
            Spacer()
            Text("Run the timer from the Pomodoro in the menu bar.")
                .font(.system(size: 11))
                .foregroundStyle(Board.muted.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 20)
        .frame(width: 230, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Board.sidebar)
    }
}

struct PomodoroBoardView: View {
    @ObservedObject var model: PomodoroModel
    @ObservedObject var store: PomodoroBoardStore
    @AppStorage("pomodoro.board.settings") private var showSettings = true

    var body: some View {
        HStack(spacing: 0) {
            if showSettings {
                BoardSettings(model: model, store: store)
                    .transition(.move(edge: .leading))
                Rectangle().fill(Board.line).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13))
                            .foregroundStyle(Board.muted)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showSettings ? "Hide timer settings" : "Show timer settings")
                    Text("Sessions")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Board.ink)
                    Spacer()
                }
                .padding(.leading, showSettings ? 20 : 84)
                .padding(.trailing, 20)
                .padding(.top, 14)
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            BoardColumn(project: nil, store: store)
                            ForEach(store.projects) { project in
                                BoardColumn(project: project, store: store).id(project.id)
                            }
                            Button {
                                let id = store.addProject()
                                DispatchQueue.main.async { withAnimation { reader.scrollTo(id, anchor: .trailing) } }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("New project")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(Board.muted)
                                .frame(width: 200, height: 110)
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Board.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Board.backdrop)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

final class PomodoroBoardWindow: NSObject, NSWindowDelegate {
    private let model: PomodoroModel
    private var window: NSWindow?

    init(model: PomodoroModel) {
        self.model = model
    }

    func present() {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            note("pomodoro board refocused")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Pomodoro"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Board.backdrop)
        window.minSize = NSSize(width: 640, height: 420)
        window.contentView = NSHostingView(rootView: PomodoroBoardView(model: model, store: .shared))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("pomodoro.board")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("pomodoro board opened projects=\(PomodoroBoardStore.shared.projects.count) sessions=\(PomodoroBoardStore.shared.sessions.count)")
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
        note("pomodoro board closed")
    }
}
