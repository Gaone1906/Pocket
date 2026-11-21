import SwiftUI

struct ZendaScheduled: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var projects: ZendaStore
    @State private var picked: String?
    @State private var weekShift = 0
    @State private var day: String?
    @State private var editing: ZendaProject?

    init(store: ScheduleStore, projects: ZendaStore, picked: String? = nil, editing: ZendaProject? = nil) {
        self.store = store
        self.projects = projects
        _picked = State(initialValue: picked)
        _editing = State(initialValue: editing)
    }

    var body: some View {
        let list = projects.sorted
        let today = store.today
        let project = projects.project(picked) ?? list.first
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                if let project {
                    ZendaProjectMenu(title: project.name, options: list.map { ($0.id, $0.name) }) { id in
                        picked = id
                        weekShift = 0
                        day = nil
                    }
                    Button { editing = project } label: {
                        Image(systemName: "pencil").font(.system(size: 17, weight: .medium))
                    }
                    .buttonStyle(ZendaCircleButton(side: 44, stroke: Zen.edge))
                    .help("Edit project")
                }
                Button { editing = fresh(today) } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(ZendaCircleButton(side: 44, stroke: Zen.ink))
                .help("New project")
            }
            if let project {
                details(project, today: today)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { project in
            ZendaProjectSheet(project: project, isNew: projects.project(project.id) == nil, routines: ZendaRoutines.all(store).isEmpty ? store.routines : ZendaRoutines.all(store)) { saved in
                projects.put(saved)
                picked = saved.id
                editing = nil
            } cancel: { editing = nil }
        }
    }

    private func fresh(_ today: String) -> ZendaProject {
        let routine = ZendaRoutines.all(store).first?.id.uuidString ?? ""
        return ZendaProject(name: "", goal: "", start: today, end: ScheduleDays.shift(today, by: 90), routine: routine, days: [1, 2, 3, 4, 5, 6, 7])
    }

    @ViewBuilder private func details(_ project: ZendaProject, today: String) -> some View {
        let anchor = min(max(today, project.start), project.end.isEmpty ? today : project.end)
        let monday = ScheduleDays.shift(ZendaDates.monday(anchor), by: weekShift * 7)
        let week = ZendaDates.span(ZendaDates.monday(project.start), monday) / 7 + 1
        let selected = day ?? (monday <= anchor && anchor <= ScheduleDays.shift(monday, by: 6) ? anchor : monday)
        let routine = project.routineRecord
        let n = min(max(0, project.dayNumber(today)), project.total)
        HStack(alignment: .center, spacing: 28) {
            HStack(spacing: 14) {
                Image(systemName: "scope").font(.system(size: 28, weight: .regular))
                Text(project.goal.isEmpty ? project.name : project.goal).font(Zen.serif(34, .bold)).lineLimit(2)
            }
            Spacer(minLength: 10)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    dateChip(project.start)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                    dateChip(project.end)
                    Spacer()
                    (Text("\(n)").foregroundStyle(Zen.ink) + Text(" / \(project.total)").foregroundStyle(Zen.muted))
                        .font(Zen.round(14, .bold))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Zen.line)
                        Capsule().fill(Zen.ink).frame(width: geo.size.width * CGFloat(n) / CGFloat(project.total))
                    }
                }
                .frame(height: 8)
            }
            .frame(width: 330)
        }
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Button { weekShift -= 1; day = nil } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)) }
                        .buttonStyle(ZendaCircleButton(side: 36, stroke: Zen.edge))
                    (Text("Week \(week)") + Text(" · \(range(monday))").foregroundStyle(Zen.muted))
                        .font(Zen.round(15, .bold))
                        .padding(.horizontal, 8)
                    Button { weekShift += 1; day = nil } label: { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)) }
                        .buttonStyle(ZendaCircleButton(side: 36, stroke: Zen.edge))
                }
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { offset in
                        let key = ScheduleDays.shift(monday, by: offset)
                        dayButton(key, project: project, routine: routine, on: key == selected)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(summary(project, routine: routine, monday: monday), id: \.0) { kind, count in
                        HStack(spacing: 8) {
                            Image(systemName: kind.symbol).font(.system(size: 14))
                            Text(kind.label)
                            Text("\(count)×").fontWeight(.bold).foregroundStyle(Zen.muted)
                        }
                        .font(Zen.round(13))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Zen.pale))
                    }
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            aside(selected, project: project, routine: routine)
        }
        .frame(maxHeight: .infinity)
    }

    private func dateChip(_ key: String) -> some View {
        Text(ZendaDates.format(key, "d MMM yyyy"))
            .font(Zen.round(14))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Zen.stone, lineWidth: 1.5))
    }

    private func range(_ monday: String) -> String {
        let sunday = ScheduleDays.shift(monday, by: 6)
        let sameMonth = ZendaDates.format(monday, "MMM") == ZendaDates.format(sunday, "MMM")
        return sameMonth ? "\(ZendaDates.format(monday, "d"))–\(ZendaDates.format(sunday, "d MMM"))" : "\(ZendaDates.format(monday, "d MMM"))–\(ZendaDates.format(sunday, "d MMM"))"
    }

    private func slots(_ day: String, project: ZendaProject, routine: ScheduleRoutine?) -> [ScheduleSlot: [ScheduleStep]] {
        guard project.applies(day), let routine, routine.runs(on: day) else { return [:] }
        var out: [ScheduleSlot: [ScheduleStep]] = [:]
        for slot in ScheduleSlot.allCases {
            let steps = routine.steps(on: day, slot)
            if !steps.isEmpty { out[slot] = steps }
        }
        return out
    }

    private func dayButton(_ key: String, project: ZendaProject, routine: ScheduleRoutine?, on: Bool) -> some View {
        let planned = slots(key, project: project, routine: routine)
        return Button { day = key } label: {
            VStack(spacing: 8) {
                Text(ZendaDates.format(key, "EEEEE")).font(Zen.round(12)).foregroundStyle(Zen.muted)
                Text(ZendaDates.format(key, "d")).font(Zen.round(20, .bold))
                ForEach(ScheduleSlot.allCases) { slot in
                    let has = planned[slot] != nil
                    Image(systemName: slot.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(has ? Zen.paper : Zen.ink.opacity(0.35))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(has ? Zen.ink : Zen.pale))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(on ? Zen.card : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(on ? Zen.ink : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summary(_ project: ZendaProject, routine: ScheduleRoutine?, monday: String) -> [(ZendaStepKind, Int)] {
        var counts: [ZendaStepKind: Int] = [:]
        for offset in 0..<7 {
            for steps in slots(ScheduleDays.shift(monday, by: offset), project: project, routine: routine).values {
                for step in steps {
                    var kind = ZendaRoutines.kind(step)
                    if kind == .review { kind = .write }
                    if kind == .scan { kind = .visualize }
                    if kind != .other { counts[kind, default: 0] += 1 }
                }
            }
        }
        return [ZendaStepKind.breathe, .visualize, .say, .write].compactMap { kind in counts[kind].map { (kind, $0) } }
    }

    private func aside(_ key: String, project: ZendaProject, routine: ScheduleRoutine?) -> some View {
        let planned = slots(key, project: project, routine: routine)
        let seconds = planned.values.flatMap { $0 }.reduce(0) { $0 + KairosPlan.estimate($1) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ZendaDates.format(key, "EEE d")).font(Zen.serif(22, .bold))
                Spacer()
                if !planned.isEmpty { Text("\(KairosPlan.minutes(seconds)) min").font(Zen.round(13)).foregroundStyle(Zen.muted) }
            }
            .padding(.bottom, 4)
            if planned.isEmpty {
                Spacer()
                ZendaEnso().frame(width: 72, height: 72).opacity(0.25).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ScheduleSlot.allCases) { slot in
                            if let steps = planned[slot] {
                                HStack(spacing: 8) {
                                    Image(systemName: slot.symbol).font(.system(size: 13, weight: .semibold))
                                    Text(slot.label)
                                }
                                .font(Zen.round(13, .bold))
                                .padding(.top, slot == .morning ? 8 : 14)
                                .padding(.bottom, 2)
                                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                                    ZendaStepRow(step: step, height: 42, size: 15)
                                    Rectangle().fill(Zen.rule).frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .top)
        .zendaCard()
    }
}

struct ZendaProjectSheet: View {
    @State var project: ZendaProject
    let isNew: Bool
    let routines: [ScheduleRoutine]
    let save: (ZendaProject) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New project" : "Edit project").font(Zen.serif(26, .bold))
            field("Name") { TextField("", text: $project.name).textFieldStyle(.plain) }
            field("Goal") { TextField("", text: $project.goal).textFieldStyle(.plain) }
            HStack(spacing: 14) {
                field("Start") { date($project.start) }
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).padding(.top, 22)
                field("End") { date($project.end) }
            }
            field("Routine") {
                Picker("", selection: $project.routine) {
                    if !routines.contains(where: { $0.id.uuidString == project.routine }) { Text("—").tag(project.routine) }
                    ForEach(routines) { routine in Text(routine.name).tag(routine.id.uuidString) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Days").font(Zen.round(12)).foregroundStyle(Zen.muted)
                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { iso in
                        let on = project.days.contains(iso)
                        Button {
                            if on { project.days.removeAll { $0 == iso } } else { project.days = (project.days + [iso]).sorted() }
                        } label: {
                            Text(["M", "T", "W", "T", "F", "S", "S"][iso - 1])
                        }
                        .buttonStyle(ZendaChip(on: on, height: 36, minWidth: 40))
                    }
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(ZendaChip(on: false, height: 40, minWidth: 90))
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(cleaned) }
                    .buttonStyle(ZendaFilled(height: 40, size: 15))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!valid)
                    .opacity(valid ? 1 : 0.45)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 460)
        .background(Zen.paper)
        .foregroundStyle(Zen.ink)
        .environment(\.colorScheme, .light)
    }

    private var cleaned: ZendaProject {
        var copy = project
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.goal = copy.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private var valid: Bool {
        !cleaned.name.isEmpty && !project.start.isEmpty && project.start <= project.end && !project.days.isEmpty && !project.routine.isEmpty
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Zen.round(12)).foregroundStyle(Zen.muted)
            content()
                .font(Zen.round(15))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
                .zendaCard(10, stroke: Zen.stone, width: 1.5)
        }
    }

    private func date(_ key: Binding<String>) -> some View {
        DatePicker("", selection: Binding(get: { ScheduleDays.date(key.wrappedValue) ?? Date() }, set: { key.wrappedValue = ScheduleDays.key($0) }),
                   displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
    }
}
