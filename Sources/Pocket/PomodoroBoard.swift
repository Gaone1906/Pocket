import Combine
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
    var started: Date? = nil
    var declared: Bool? = nil

    var isDeclared: Bool { declared == true }
}

final class PomodoroBoardStore: ObservableObject {
    static let shared = PomodoroBoardStore()

    @Published private(set) var projects: [PomodoroProject] = []
    @Published private(set) var sessions: [PomodoroSession] = []
    private let file = PocketData.board

    private struct Saved: Codable {
        var projects: [PomodoroProject]
        var sessions: [PomodoroSession]
    }

    private init() {
        let vault = DataVault.shared
        vault.register("board") { [weak self] data in self?.merge(data) }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
                projects = saved.projects
                sessions = saved.sessions
                note("pomodoro board loaded projects=\(projects.count) sessions=\(sessions.count)")
                return
            } catch {
                note("pomodoro board load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: "board")
            }
        }
        guard let (saved, snap) = vault.recover("board", decode: { try JSONDecoder().decode(Saved.self, from: $0) }) else {
            note("pomodoro board starting empty path=\(file.path) snapshots=0")
            return
        }
        projects = saved.projects
        sessions = saved.sessions
        note("pomodoro board recovered from=\(snap.url.path) projects=\(projects.count) sessions=\(sessions.count)")
        save()
    }

    func merge(_ data: Data) {
        do {
            let incoming = try JSONDecoder().decode(Saved.self, from: data)
            if let current = try? JSONEncoder().encode(Saved(projects: projects, sessions: sessions)) {
                DataVault.shared.keepAside(current, name: "board", reason: "before-merge")
            }
            let knownProjects = Set(projects.map(\.id))
            let knownSessions = Set(sessions.map(\.id))
            let newProjects = incoming.projects.filter { !knownProjects.contains($0.id) }
            let newSessions = incoming.sessions.filter { !knownSessions.contains($0.id) }
            projects += newProjects
            sessions = (sessions + newSessions).sorted { $0.ended < $1.ended }
            save()
            note("pomodoro board merged projectsAdded=\(newProjects.count) sessionsAdded=\(newSessions.count) sessions=\(sessions.count)")
        } catch {
            note("pomodoro board merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    var snapshots: [(snapshot: VaultSnapshot, sessions: Int, minutes: Int)] {
        DataVault.shared.snapshots("board").compactMap { snap in
            guard let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: snap.url)) else { return nil }
            return (snap, saved.sessions.count, saved.sessions.reduce(0) { $0 + $1.minutes })
        }
    }

    func restore(_ snap: VaultSnapshot) {
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: snap.url))
            if let current = try? JSONEncoder().encode(Saved(projects: projects, sessions: sessions)) {
                DataVault.shared.keepAside(current, name: "board", reason: "before-restore")
            }
            let before = sessions.count
            projects = saved.projects
            sessions = saved.sessions
            save()
            note("pomodoro board restored from=\(snap.url.path) sessionsBefore=\(before) sessionsAfter=\(sessions.count)")
        } catch {
            note("pomodoro board restore failed from=\(snap.url.path) error=\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Saved(projects: projects, sessions: sessions))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: "board", count: sessions.count)
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

    func declare(minutes: Int, ended: Date, started: Date?, project: UUID?) {
        let session = PomodoroSession(id: UUID(), ended: ended, minutes: minutes, project: project, started: started, declared: true)
        sessions.append(session)
        sessions.sort { $0.ended < $1.ended }
        save()
        note("pomodoro session declared session=\(session.id) minutes=\(minutes) ended=\(ended.ISO8601Format()) started=\(started?.ISO8601Format() ?? "none") project=\(project?.uuidString ?? "unassigned") total=\(sessions.count)")
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
        let hue = (0..<Board.hueCount).first { !used.contains($0) } ?? projects.count % Board.hueCount
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
    static var theme: BoardTheme { BoardThemeStore.shared.theme }
    static var backdrop: Color { theme.backdrop }
    static var sidebar: Color { theme.sidebar }
    static var column: Color { theme.card }
    static var line: Color { theme.line }
    static var muted: Color { theme.muted }
    static var ink: Color { theme.ink }
    static var faint: Color { theme.faint }
    static var accent: Color { theme.accent }
    static var accentInk: Color { theme.accentInk }
    static var accentStyle: AnyShapeStyle { theme.accentStyle }
    static var accentInkStyle: AnyShapeStyle { theme.accentInkStyle }
    static var shadow: Color { theme.shadow }
    static let hueCount = BoardTheme.projectOffsets.count

    static let glide = Animation.smooth(duration: 0.3)

    static func hue(_ index: Int) -> Color { theme.projectTint(index) }

    static func sessionLabel(_ session: PomodoroSession) -> String {
        guard session.isDeclared else {
            return "\(session.minutes) min · \(session.ended.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
        }
        let day = session.ended.formatted(.dateTime.day().month(.abbreviated))
        guard let started = session.started else { return "\(session.minutes) min · \(day) · declared" }
        let span = "\(started.formatted(date: .omitted, time: .shortened))–\(session.ended.formatted(date: .omitted, time: .shortened))"
        return "\(session.minutes) min · \(day) \(span) · declared"
    }

    static func units(_ sessions: [PomodoroSession]) -> Double {
        (Double(sessions.reduce(0) { $0 + $1.minutes }) / Double(TallyStick.fullMinutes) * 10).rounded() / 10
    }

    static func unitsLabel(_ units: Double) -> String {
        units.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func days(_ sessions: [PomodoroSession]) -> [(day: Date, sessions: [PomodoroSession])] {
        let calendar = Calendar.current
        return Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.ended) }
            .map { (day: $0.key, sessions: $0.value.sorted { $0.ended < $1.ended }) }
            .sorted { $0.day > $1.day }
    }

    static func dayDate(_ day: Date) -> String {
        Calendar.current.isDate(day, equalTo: Date(), toGranularity: .year)
            ? day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : day.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func dayTag(_ day: Date) -> String? {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return nil
    }

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
        show([session], store: store)
    }

    static func show(_ sessions: [PomodoroSession], store: PomodoroBoardStore) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if sessions.count == 1, let session = sessions.first {
            items(for: session, store: store).forEach(menu.addItem)
        } else {
            for session in sessions {
                let entry = NSMenuItem(title: label(session), action: nil, keyEquivalent: "")
                let sub = NSMenu()
                sub.autoenablesItems = false
                items(for: session, store: store).dropFirst(2).forEach(sub.addItem)
                entry.submenu = sub
                menu.addItem(entry)
            }
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func label(_ session: PomodoroSession) -> String {
        Board.sessionLabel(session)
    }

    private static func items(for session: PomodoroSession, store: PomodoroBoardStore) -> [NSMenuItem] {
        let title = NSMenuItem(title: label(session), action: nil, keyEquivalent: "")
        title.isEnabled = false
        var items = [title, .separator()]
        items.append(item("Unassigned", on: session.project == nil) { store.assign(session.id, to: nil) })
        for project in store.projects {
            items.append(item(project.name.isEmpty ? "Untitled" : project.name, on: session.project == project.id) { store.assign(session.id, to: project.id) })
        }
        items.append(.separator())
        items.append(item("Delete session", on: false) { store.deleteSession(session.id) })
        return items
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
            .fill(Board.accentStyle)
            .frame(width: 10, height: 10)
            .shadow(color: Board.accent.opacity(bright ? 0.95 : 0.55), radius: bright ? 7 : 4)
            .shadow(color: Board.accent.opacity(0.35), radius: 12)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}

struct TallyStick: Identifiable {
    static let fullMinutes = 25

    let sessions: [PomodoroSession]
    let index: Int
    let fraction: CGFloat

    var id: String { "\(index)-\(sessions.first?.id.uuidString ?? "")" }

    static func sticks(for sessions: [PomodoroSession]) -> [TallyStick] {
        var spans: [(session: PomodoroSession, start: Int, end: Int)] = []
        var total = 0
        for session in sessions {
            let minutes = max(1, session.minutes)
            spans.append((session, total, total + minutes))
            total += minutes
        }
        return stride(from: 0, to: total, by: fullMinutes).enumerated().map { index, start in
            let end = min(start + fullMinutes, total)
            let inside = spans.filter { $0.start < end && $0.end > start }.map(\.session)
            return TallyStick(sessions: inside, index: index, fraction: CGFloat(end - start) / CGFloat(fullMinutes))
        }
    }

    static func groups(for sticks: [TallyStick]) -> [[TallyStick]] {
        var groups: [[TallyStick]] = []
        var current: [TallyStick] = []
        for stick in sticks {
            if current.count == 4 {
                let strikes = stick.fraction == 1 && current.allSatisfy { $0.fraction == 1 }
                if strikes {
                    groups.append(current + [stick])
                    current = []
                    continue
                }
                groups.append(current)
                current = []
            }
            current.append(stick)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}

private struct TallyGroup: View {
    let sticks: [TallyStick]
    let tint: Color
    let tap: ([PomodoroSession]) -> Void

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
            .fill(Board.theme.sheen(tint))
            .opacity(stick.fraction < 1 ? 0.75 : 1)
            .frame(width: 3, height: max(6, length * stick.fraction))
            .padding(.horizontal, 4)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
            .onTapGesture { tap(stick.sessions) }
            .draggable(stick.sessions.last?.id.uuidString ?? "")
            .help(stick.sessions.map(Board.sessionLabel).joined(separator: "\n"))
    }
}

private struct SessionMarks: View {
    let sessions: [PomodoroSession]
    let assigned: Bool
    let tint: Color
    @ObservedObject var store: PomodoroBoardStore

    var body: some View {
        if assigned {
            let groups = TallyStick.groups(for: TallyStick.sticks(for: sessions))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 20)], alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.first!.id) { group in
                    TallyGroup(sticks: group, tint: tint) { SessionMenu.show($0, store: store) }
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 22, maximum: 22), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(sessions) { session in
                    GlowDot()
                        .onTapGesture { SessionMenu.show(session, store: store) }
                        .draggable(session.id.uuidString)
                        .help(Board.sessionLabel(session))
                }
            }
        }
    }
}

private struct BoardCalendar: View {
    @ObservedObject var store: PomodoroBoardStore

    private struct Lane: Identifiable {
        let project: PomodoroProject?
        var id: String { project?.id.uuidString ?? "unassigned" }
        var tint: Color { project.map { Board.hue($0.hue) } ?? Board.accent }
        var name: String { project.map { $0.name.isEmpty ? "Untitled" : $0.name } ?? "Unassigned" }
    }

    var body: some View {
        let lanes = [Lane(project: nil)] + store.projects.map { Lane(project: $0) }
        let days = Board.days(store.sessions)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Color.clear.frame(width: 150, height: 1)
                    ForEach(lanes) { lane in
                        HStack(spacing: 8) {
                            Circle().fill(lane.tint).frame(width: 7, height: 7)
                            Text(lane.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Board.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Board.unitsLabel(Board.units(store.sessions(in: lane.project?.id))))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Board.muted)
                        }
                        .padding(.horizontal, 16)
                        .frame(width: 260, height: 46)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Board.line, lineWidth: 1))
                    }
                }
                if days.isEmpty {
                    Text("Finished sessions show up here, one row per day")
                        .font(.system(size: 12))
                        .foregroundStyle(Board.muted)
                        .padding(.leading, 164)
                        .padding(.top, 10)
                }
                ForEach(days, id: \.day) { entry in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Board.dayDate(entry.day))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Board.ink)
                                .lineLimit(1)
                            Text([Board.dayTag(entry.day), "\(Board.unitsLabel(Board.units(entry.sessions))) sessions"].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(Board.muted)
                        }
                        .padding(14)
                        .frame(width: 150, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Board.sidebar))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Board.line, lineWidth: 1))
                        ForEach(lanes) { lane in
                            let sessions = entry.sessions.filter { $0.project == lane.project?.id }
                            VStack(alignment: .leading) {
                                if sessions.isEmpty {
                                    Text("–")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Board.faint)
                                } else {
                                    SessionMarks(sessions: sessions, assigned: lane.project != nil, tint: lane.tint, store: store)
                                }
                            }
                            .padding(16)
                            .frame(width: 260, alignment: .topLeading)
                            .frame(minHeight: 72, maxHeight: .infinity, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Board.line, lineWidth: 1))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .defaultScrollAnchor(.topLeading)
    }
}

private struct BoardColumn: View {
    let project: PomodoroProject?
    @ObservedObject var store: PomodoroBoardStore
    let declare: (UUID?) -> Void
    @State private var name = ""
    @State private var targeted = false
    @FocusState private var editing: Bool

    private var sessions: [PomodoroSession] { store.sessions(in: project?.id) }
    private var tint: Color { project.map { Board.hue($0.hue) } ?? Board.accent }

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
                Text(Board.unitsLabel(Board.units(sessions)))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Board.muted)
                if let project {
                    Menu {
                        Button("Declare a session…") { declare(project.id) }
                        Divider()
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
                SessionMarks(sessions: sessions.sorted { $0.ended < $1.ended }, assigned: project != nil, tint: tint, store: store)
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(targeted ? tint.opacity(0.8) : Board.line, lineWidth: targeted ? 1.5 : 1))
        .contextMenu {
            Button("Declare a session…") { declare(project?.id) }
            if let project {
                Divider()
                Button("Delete project", role: .destructive) { store.deleteProject(project.id) }
            }
        }
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
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Board.muted)
            Spacer(minLength: 4)
            step("minus", -1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Board.ink)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(Board.muted)
            }
            .frame(width: 66)
            step("plus", 1)
        }
    }

    private func step(_ symbol: String, _ delta: Int) -> some View {
        Button {
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Board.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Board.column))
                .overlay(Circle().stroke(Board.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct BoardSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Board.muted)
    }
}

private struct BoardStats: View {
    @ObservedObject var store: PomodoroBoardStore

    var body: some View {
        let today = store.sessions.filter { Calendar.current.isDateInToday($0.ended) }
        VStack(alignment: .leading, spacing: 14) {
            card("TODAY", today)
            card("ALL TIME", store.sessions)
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 20)
        .frame(width: 220, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Board.sidebar)
    }

    private func card(_ title: String, _ sessions: [PomodoroSession]) -> some View {
        let minutes = sessions.reduce(0) { $0 + $1.minutes }
        let units = Board.units(sessions)
        return VStack(alignment: .leading, spacing: 10) {
            BoardSectionTitle(text: title)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Board.unitsLabel(units))
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Board.accentInkStyle)
                    Text(units == 1 ? "session" : "sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(Board.muted)
                }
                Rectangle().fill(Board.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(minutes == 0 ? "0m" : Board.duration(minutes))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Board.ink)
                    Text("focused")
                        .font(.system(size: 11))
                        .foregroundStyle(Board.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Board.column))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Board.line, lineWidth: 1))
        }
        .padding(.top, 8)
    }
}

private struct BoardSettingsPanel: View {
    @ObservedObject var model: PomodoroModel
    @ObservedObject var themes: BoardThemeStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Board.ink)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Board.muted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Board.column))
                        .overlay(Circle().stroke(Board.line, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close settings")
            }
            BoardSectionTitle(text: "TIMER").padding(.top, 6)
            SettingRow(title: "Focus", value: $model.focusMinutes, range: 1...120, unit: "min")
            SettingRow(title: "Short break", value: $model.breakMinutes, range: 1...60, unit: "min")
            SettingRow(title: "Long break", value: $model.longBreakMinutes, range: 1...90, unit: "min")
            SettingRow(title: "Long break after", value: $model.longEvery, range: 2...12, unit: "sessions")
            Rectangle().fill(Board.line).frame(height: 1).padding(.vertical, 4)
            HStack(alignment: .firstTextBaseline) {
                BoardSectionTitle(text: "THEME")
                Spacer()
                Text(themes.theme.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Board.accentInkStyle)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 14) {
                ForEach(Array(stride(from: 0, to: BoardTheme.all.count, by: 5)), id: \.self) { start in
                    GridRow {
                        ForEach(BoardTheme.all[start..<min(start + 5, BoardTheme.all.count)]) { theme in
                            swatch(theme)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Board.line).frame(height: 1).padding(.vertical, 4)
            BoardBackupSection(store: PomodoroBoardStore.shared)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: 280, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Board.sidebar)
    }

    private func swatch(_ theme: BoardTheme) -> some View {
        let on = theme == themes.theme
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { themes.theme = theme }
        } label: {
            Circle()
                .fill(theme.swatchStyle)
                .overlay(Circle().stroke(theme.swatchEdge, lineWidth: 1))
                .frame(width: 32, height: 32)
                .padding(3)
                .overlay(Circle().stroke(on ? theme.swatchRing : .clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.name)
    }
}

private struct BoardBackupSection: View {
    @ObservedObject var store: PomodoroBoardStore
    @ObservedObject var vault = DataVault.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoardSectionTitle(text: "BACKUP")
            line("Daily copy", vault.lastSnapshot.map { "saved \(Self.ago($0))" } ?? "none yet")
            if vault.repoURL != nil {
                line("GitHub", vault.syncProblem ?? vault.lastSync.map { "synced \(Self.ago($0))" } ?? "waiting to sync", warn: vault.syncProblem != nil)
            }
            if let folder = vault.mirrorFolder {
                line("Copy", folder.lastPathComponent == "Pocket Backups" ? "Google Drive" : folder.lastPathComponent)
            }
            if !vault.incoming.isEmpty {
                HStack(spacing: 8) {
                    Button("Bring them in") { vault.bringIn() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Board.accentInkStyle)
                        .help("Adds what's on GitHub to this Mac, keeping everything here too")
                    Spacer()
                    Button("Keep this Mac's") { confirmKeep() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Board.muted)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    let snaps = store.snapshots
                    if snaps.isEmpty { Text("No daily copies yet") }
                    ForEach(snaps, id: \.snapshot.id) { entry in
                        Button("\(entry.snapshot.day.formatted(.dateTime.day().month(.abbreviated).year())) · \(entry.sessions) sessions · \(Board.duration(entry.minutes))") {
                            confirm(entry.snapshot, sessions: entry.sessions)
                        }
                    }
                } label: {
                    Text("Restore…").font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(Board.ink)
                Spacer()
                Button("Show backups") { vault.showInFinder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Board.muted)
            }
        }
    }

    private func line(_ title: String, _ value: String, warn: Bool = false) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(Board.muted)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(warn ? Color.red.opacity(0.8) : Board.ink).lineLimit(1)
        }
    }

    private func confirm(_ snap: VaultSnapshot, sessions: Int) {
        let alert = NSAlert()
        alert.messageText = "Restore the board from \(snap.day.formatted(.dateTime.day().month(.wide).year()))?"
        alert.informativeText = "The board goes back to \(sessions) sessions. Your current board (\(store.sessions.count) sessions) is kept as its own backup first, so this can be undone."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            note("pomodoro board restore cancelled from=\(snap.url.path)")
            return
        }
        store.restore(snap)
    }

    private func confirmKeep() {
        let alert = NSAlert()
        alert.messageText = "Replace the GitHub copy with this Mac's data?"
        alert.informativeText = "GitHub has data this Mac doesn't have. Replacing drops it from the latest copy; it stays in the repo's history."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            note("pocket vault keep local cancelled")
            return
        }
        vault.keepThisMac()
    }

    private static func ago(_ date: Date) -> String {
        date.timeIntervalSinceNow > -60 ? "just now" : date.formatted(.relative(presentation: .named))
    }
}

struct PomodoroBoardView: View {
    @ObservedObject var model: PomodoroModel
    @ObservedObject var store: PomodoroBoardStore
    @ObservedObject var themes = BoardThemeStore.shared
    @AppStorage("pomodoro.board.stats") private var showStats = true
    @AppStorage("pomodoro.board.panel") private var showPanel = false
    @AppStorage("pomodoro.board.mode") private var mode = "sessions"
    @State private var declaring: DeclareTarget?

    var body: some View {
        ZStack {
        HStack(spacing: 0) {
            if showStats {
                HStack(spacing: 0) {
                    BoardStats(store: store)
                    Rectangle().fill(Board.line).frame(width: 1)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(Board.glide) { showStats.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13))
                            .foregroundStyle(Board.muted)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showStats ? "Hide stats" : "Show stats")
                    BoardModeToggle(mode: $mode)
                    Spacer()
                    BoardSettingsButton(open: showPanel) {
                        note("pomodoro board settings panel open=\(!showPanel)")
                        withAnimation(Board.glide) { showPanel.toggle() }
                    }
                }
                .padding(.leading, showStats ? 20 : 84)
                .padding(.trailing, 20)
                .padding(.top, 12)
                ZStack(alignment: .topLeading) {
                if mode == "calendar" {
                    BoardCalendar(store: store)
                        .transition(.opacity.combined(with: .offset(x: 36)))
                } else {
                    ScrollViewReader { reader in
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 14) {
                                BoardColumn(project: nil, store: store, declare: openDeclare)
                                ForEach(store.projects) { project in
                                    BoardColumn(project: project, store: store, declare: openDeclare).id(project.id)
                                }
                                Button {
                                    let id = store.addProject()
                                    DispatchQueue.main.async { withAnimation(.smooth(duration: 0.2)) { reader.scrollTo(id, anchor: .trailing) } }
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
                    .transition(.opacity.combined(with: .offset(x: -36)))
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
            if showPanel {
                HStack(spacing: 0) {
                    Rectangle().fill(Board.line).frame(width: 1)
                    BoardSettingsPanel(model: model, themes: themes) {
                        withAnimation(Board.glide) { showPanel = false }
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
            if let target = declaring {
                Color.black.opacity(themes.theme.isDark ? 0.4 : 0.18)
                    .ignoresSafeArea()
                    .onTapGesture { closeDeclare() }
                    .transition(.opacity)
                DeclareSessionCard(project: store.project(target.project), store: store, close: closeDeclare)
                    .id(target.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.15), value: declaring?.id)
        .animation(Board.glide, value: mode)
        .animation(Board.glide, value: showStats)
        .animation(Board.glide, value: showPanel)
        .id(themes.theme.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Board.backdrop)
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
    }
}

extension PomodoroBoardView {
    private func openDeclare(_ project: UUID?) {
        note("pomodoro declare opened project=\(project?.uuidString ?? "unassigned")")
        declaring = DeclareTarget(project: project)
    }

    private func closeDeclare() {
        declaring = nil
    }
}

struct DeclareTarget: Identifiable, Equatable {
    let id = UUID()
    let project: UUID?
}

private struct BoardSettingsButton: View {
    let open: Bool
    let action: () -> Void

    var body: some View {
        let icon = Image(systemName: "slider.horizontal.3")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(open ? Board.accentInkStyle : AnyShapeStyle(Board.muted))
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        Button(action: action) {
            if #available(macOS 26, *) {
                icon.glassEffect(.regular.interactive(), in: Circle())
            } else {
                icon
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Board.line, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .help(open ? "Close settings" : "Settings")
    }
}

private struct BoardModeToggle: View {
    @Binding var mode: String
    @Namespace private var pill

    private let options = [("Sessions", "sessions"), ("Calendar", "calendar")]

    var body: some View {
        if #available(macOS 26, *) {
            segments
                .padding(4)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            segments
                .padding(4)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Board.line, lineWidth: 1))
        }
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { title, value in
                Button {
                    guard mode != value else { return }
                    note("pomodoro board view mode=\(value)")
                    withAnimation(Board.glide) { mode = value }
                } label: {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(mode == value ? Board.ink : Board.muted.opacity(0.7))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if mode == value {
                                Capsule()
                                    .fill(Board.theme.pill)
                                    .shadow(color: Board.shadow, radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

final class PomodoroBoardWindow: NSObject, NSWindowDelegate {
    private let model: PomodoroModel
    private var window: NSWindow?
    private var themeWatch: AnyCancellable?

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
        window.appearance = Board.theme.appearance
        window.backgroundColor = NSColor(Board.backdrop)
        themeWatch = BoardThemeStore.shared.$theme.sink { [weak window] theme in
            window?.appearance = theme.appearance
            window?.backgroundColor = NSColor(theme.backdrop)
        }
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
        themeWatch = nil
        NSApp.setActivationPolicy(.accessory)
        note("pomodoro board closed")
    }
}
