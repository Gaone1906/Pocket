import SwiftUI

enum ZendaRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case all = "All"
}

struct ZendaReview: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var projects: ZendaStore
    @ObservedObject var journal: KairosJournal
    let open: (String) -> Void
    @State private var picked: String?
    @State private var range: ZendaRange = .week

    var body: some View {
        let today = store.today
        let ledger = ZendaLedger(store)
        let project = projects.project(picked)
        let pool = ledger.scope(project)
        let days = span(today, project: project, pool: pool)
        let sessions = days.flatMap { ledger.sessions(on: $0, in: pool) }
        let seconds = days.reduce(0) { $0 + ledger.doneSeconds(on: $1, in: pool) }
        let entries = ZendaBooks.entries(journal).filter { entry in
            days.contains(entry.day) && (project == nil || entry.routine == project?.routine)
        }
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZendaProjectMenu(title: project?.name ?? "All projects",
                                 options: [(id: nil, name: "All projects")] + projects.sorted.map { (id: Optional($0.id), name: $0.name) }) { picked = $0 }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(ZendaRange.allCases, id: \.self) { value in
                        Button(value.rawValue) { range = value }.buttonStyle(ZendaChip(on: value == range, height: 34, minWidth: 64, bordered: false))
                    }
                }
                .padding(4)
                .background(Capsule().fill(Zen.pale))
            }
            HStack(spacing: 14) {
                stat("flame", "\(ledger.streak(today: today, in: pool))", "streak")
                stat("checkmark", "\(sessions.filter(\.finished).count)", "sessions", suffix: "/\(sessions.filter { $0.day <= today }.count)")
                stat("hourglass", String(format: "%.1f", Double(seconds) / 3600), "h present")
                stat("book.closed", "\(entries.count)", "entries")
            }
            HStack(alignment: .top, spacing: 14) {
                heatmap(today, ledger: ledger, project: project, pool: pool)
                adherence(today, ledger: ledger)
                    .frame(width: 300)
            }
            HStack(alignment: .top, spacing: 14) {
                minutes(today, ledger: ledger, pool: pool)
                shelf(ZendaBooks.entries(journal).filter { project == nil || $0.routine == project?.routine })
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func span(_ today: String, project: ZendaProject?, pool: [ScheduleRoutine]) -> [String] {
        let first: String
        switch range {
        case .week: first = ZendaDates.monday(today)
        case .month: first = ScheduleDays.shift(today, by: -29)
        case .all: first = project?.start ?? pool.map(\.starts).min() ?? today
        }
        let count = max(0, ZendaDates.span(first, today)) + 1
        return (0..<min(count, 2000)).map { ScheduleDays.shift(first, by: $0) }
    }

    private func stat(_ symbol: String, _ value: String, _ label: String, suffix: String = "") -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Zen.paper)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Zen.ink))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(value).font(Zen.round(30, .bold)).monospacedDigit()
                    if !suffix.isEmpty { Text(suffix).font(Zen.round(16, .bold)).foregroundStyle(Zen.muted) }
                }
                Text(label).font(Zen.round(12)).foregroundStyle(Zen.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .zendaCard(20)
    }

    private func heatmap(_ today: String, ledger: ZendaLedger, project: ZendaProject?, pool: [ScheduleRoutine]) -> some View {
        let start = ZendaDates.monday(project?.start ?? pool.map(\.starts).min() ?? today)
        let end = project?.end ?? projects.projects.map(\.end).max() ?? ScheduleDays.shift(today, by: 7 * 8)
        let weeks = max(1, min(60, ZendaDates.span(start, end) / 7 + 1))
        return VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let side = max(6, min(22, (geo.size.width - CGFloat(weeks - 1) * gap) / CGFloat(weeks)))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                cell(ScheduleDays.shift(start, by: week * 7 + row), today: today, end: end, ledger: ledger, pool: pool)
                                    .frame(width: side, height: side)
                            }
                        }
                    }
                }
            }
            .frame(height: 7 * 22 + 6 * 3)
            HStack {
                Text(ZendaDates.format(start, "d MMM"))
                Spacer()
                Text(ZendaDates.format(end, "d MMM"))
            }
            .font(Zen.round(12))
            .foregroundStyle(Zen.muted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .zendaCard()
    }

    @ViewBuilder private func cell(_ day: String, today: String, end: String, ledger: ZendaLedger, pool: [ScheduleRoutine]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if day > end {
            Color.clear
        } else if day > today {
            shape.strokeBorder(Zen.empty, lineWidth: 1.5)
        } else {
            let fill = ledger.fill(on: day, in: pool)
            let color = fill.total == 0 ? Zen.empty.opacity(0.5) : fill.done >= fill.total ? Zen.ink : fill.done > 0 ? Zen.mid : Zen.empty
            shape.fill(color)
                .overlay(shape.stroke(day == today ? Zen.ink : Color.clear, lineWidth: 2).padding(-2))
        }
    }

    private func adherence(_ today: String, ledger: ZendaLedger) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(projects.sorted) { project in
                let pool = ledger.scope(project)
                let days = (0..<max(1, min(project.total, ZendaDates.span(project.start, today) + 1))).map { ScheduleDays.shift(project.start, by: $0) }
                let fills = days.filter { $0 <= today }.map { ledger.fill(on: $0, in: pool) }
                let done = fills.reduce(0) { $0 + $1.done }
                let total = fills.reduce(0) { $0 + $1.total }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(project.name).font(Zen.round(14, .bold)).lineLimit(1)
                        Spacer()
                        Text(total == 0 ? "0" : "\(done)/\(total)").font(Zen.round(13, .bold)).foregroundStyle(Zen.muted).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Zen.pale)
                            Capsule().fill(Zen.ink).frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total))
                        }
                    }
                    .frame(height: 8)
                }
            }
            if projects.projects.isEmpty {
                Text("No projects yet").font(Zen.round(14)).foregroundStyle(Zen.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .zendaCard()
    }

    private func minutes(_ today: String, ledger: ZendaLedger, pool: [ScheduleRoutine]) -> some View {
        let days = (0..<14).map { ScheduleDays.shift(today, by: $0 - 13) }
        let values = days.map { ledger.doneSeconds(on: $0, in: pool) / 60 }
        let top = max(1, values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 4) {
                        Text(values[index] > 0 ? "\(values[index])" : "").font(Zen.round(10)).foregroundStyle(Zen.muted)
                        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 4)
                            .fill(day == today ? Zen.mid : Zen.ink)
                            .frame(height: max(2, 92 * CGFloat(values[index]) / CGFloat(top)))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)
            HStack {
                Text(ZendaDates.format(days[0], "d MMM"))
                Spacer()
                Text(ZendaDates.format(today, "d MMM"))
            }
            .font(Zen.round(12))
            .foregroundStyle(Zen.muted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .zendaCard()
    }

    private func shelf(_ entries: [KairosEntry]) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(ZendaBooks.all.enumerated()), id: \.offset) { index, book in
                let count = entries.filter { ($0.tag ?? "note") == book.tag }.count
                Button { open(book.tag) } label: {
                    ZendaSpine(title: book.name, count: count, style: index)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 300)
        .zendaCard()
    }
}

struct ZendaSpine: View {
    let title: String
    let count: Int
    let style: Int

    var body: some View {
        let fill: Color = [Zen.ink, Zen.umber, Zen.pale, Zen.ink, Zen.mid, Zen.card][style % 6]
        let dark = style % 6 != 2 && style % 6 != 5
        VStack {
            Text("\(count)").font(Zen.round(13, .bold)).monospacedDigit()
            Spacer(minLength: 4)
            Text(title)
                .font(Zen.round(13, .bold))
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 20, height: 70)
        }
        .foregroundStyle(dark ? Zen.paper : Zen.ink)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5, bottomTrailingRadius: 12, topTrailingRadius: 12).fill(fill))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5, bottomTrailingRadius: 12, topTrailingRadius: 12)
            .stroke(Zen.ink, lineWidth: dark ? 0 : 1.5))
        .contentShape(Rectangle())
    }
}

struct ZendaBookView: View {
    @ObservedObject var journal: KairosJournal
    @ObservedObject var projects: ZendaStore
    let back: () -> Void
    @State private var tag: String
    @State private var page = -1
    @State private var picking = false
    @State private var goTo = Date()

    init(journal: KairosJournal, projects: ZendaStore, tag: String, back: @escaping () -> Void) {
        self.journal = journal
        self.projects = projects
        self.back = back
        _tag = State(initialValue: tag)
    }

    private var days: [(day: String, entries: [KairosEntry])] {
        let list = ZendaBooks.entries(journal).filter { ($0.tag ?? "note") == tag && !$0.body.isEmpty }
        return Dictionary(grouping: list, by: \.day).sorted { $0.key < $1.key }.map { (day: $0.key, entries: $0.value) }
    }

    var body: some View {
        let all = days
        let last = max(0, all.count - 1)
        let left = page < 0 ? max(0, all.count - 2) : min(page, last)
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(ZendaCircleButton(side: 40, stroke: Zen.edge))
                .keyboardShortcut(.cancelAction)
                ForEach(ZendaBooks.all) { book in
                    Button(book.name) {
                        tag = book.tag
                        page = -1
                    }
                    .buttonStyle(ZendaChip(on: book.tag == tag, height: 36))
                }
                Spacer()
                Button { picking = true } label: {
                    Image(systemName: "calendar").font(.system(size: 17, weight: .regular))
                }
                .buttonStyle(ZendaCircleButton(side: 40, stroke: Zen.edge))
                .help("Go to a date")
                .popover(isPresented: $picking) {
                    VStack(spacing: 10) {
                        DatePicker("", selection: $goTo, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                        Button("Go") {
                            let target = ScheduleDays.key(goTo)
                            page = all.firstIndex { $0.day >= target } ?? last
                            picking = false
                        }
                        .buttonStyle(ZendaFilled(height: 36, size: 14))
                    }
                    .padding(14)
                }
            }
            HStack(spacing: 18) {
                arrow("chevron.left", enabled: left > 0) { page = max(0, left - 2) }
                HStack(spacing: 0) {
                    sheet(all.indices.contains(left) ? all[left] : nil, number: left + 1)
                    Rectangle().fill(Zen.ink.opacity(0.12)).frame(width: 1)
                    sheet(all.indices.contains(left + 1) ? all[left + 1] : nil, number: left + 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Zen.line, lineWidth: 1))
                .shadow(color: Zen.ink.opacity(0.08), radius: 22, y: 18)
                arrow("chevron.right", enabled: left + 2 <= last) { page = min(last, left + 2) }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func arrow(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(ZendaCircleButton(side: 44, stroke: Zen.stone))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .keyboardShortcut(symbol == "chevron.left" ? .leftArrow : .rightArrow, modifiers: [])
    }

    private func sheet(_ item: (day: String, entries: [KairosEntry])?, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(ZendaDates.format(item.day, "EEE d MMM")).font(Zen.serif(22, .semibold))
                    Text(projects.sorted.filter { $0.covers(item.day) && item.entries.map(\.routine).contains($0.routine) }.map(\.name).joined(separator: " · "))
                        .font(Zen.round(13))
                        .foregroundStyle(Zen.muted)
                        .lineLimit(1)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(ScheduleSlot.allCases, id: \.self) { slot in
                            let here = item.entries.filter { $0.slot == slot.rawValue }
                            if !here.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: slot.symbol)
                                    Text(slot.label)
                                }
                                .font(Zen.round(13, .bold))
                                .padding(.top, 6)
                                ForEach(Array(lines(here).enumerated()), id: \.offset) { index, line in
                                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                                        Text("\(index + 1)").font(Zen.round(13, .bold)).foregroundStyle(Zen.muted).frame(width: 14, alignment: .leading)
                                        Text(line).font(Zen.serif(18, .regular)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.bottom, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xEEE9DF)).frame(height: 1) }
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            } else {
                Spacer()
                ZendaEnso().frame(width: 140, height: 140).opacity(0.08).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            Text(item == nil ? " " : "\(number)").font(Zen.round(12)).foregroundStyle(Zen.muted).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Zen.leaf)
    }

    private func lines(_ entries: [KairosEntry]) -> [String] {
        entries.flatMap { entry -> [String] in
            if let lines = entry.lines, lines.contains(where: { !$0.isEmpty }) { return lines.filter { !$0.isEmpty } }
            return [entry.text ?? entry.body].filter { !$0.isEmpty }
        }
    }
}
