import SwiftUI

struct ZendaStart: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var projects: ZendaStore
    @State private var visualizeFor: String?
    @State private var affirmFor: String?

    var body: some View {
        let routines = ZendaRoutines.all(store)
        let list = projects.sorted
        let today = store.today
        let current = list.first { $0.applies(today) }?.id ?? list.first?.id
        VStack(alignment: .leading, spacing: 24) {
            Text("Start").font(Zen.serif(40, .bold))
            Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                GridRow {
                    breathe(routines)
                    projectTile("Visualize", .visualize, choices: [3, 6, 10], selection: $visualizeFor, fallback: current, list: list, routines: routines)
                    projectTile("Affirm", .say, choices: [3, 5, 10], selection: $affirmFor, fallback: current, list: list, routines: routines)
                }
                GridRow {
                    scan(routines)
                    journal(routines).gridCellColumns(2)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tile<Content: View>(_ symbol: String, _ name: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            icon(symbol)
            Text(name).font(Zen.round(19, .bold))
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .zendaCard(24)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(Zen.paper)
            .frame(width: 52, height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Zen.ink))
    }

    private func minutes(_ choices: [Int], usual: Int?, start: @escaping (Int) -> Void) -> some View {
        let near = usual.flatMap { u in choices.min { abs($0 - u) < abs($1 - u) } }
        return HStack(spacing: 6) {
            ForEach(choices, id: \.self) { value in
                Button("\(value)") { start(value) }.buttonStyle(ZendaChip(on: value == near))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func breathe(_ routines: [ScheduleRoutine]) -> some View {
        let found = ZendaAdhoc.template(.breathe, in: routines)
        let pattern = found.map { KairosPlan.pattern(KairosPlan.run($0)) } ?? [4, 4, 4, 4]
        return tile(ZendaStepKind.breathe.symbol, "Box breathing") {
            Text(pattern.map(String.init).joined(separator: " · ")).font(Zen.round(13)).foregroundStyle(Zen.muted)
            minutes([2, 4, 8, 12], usual: ZendaAdhoc.minutes(.breathe, in: routines)) { value in
                ZendaAdhoc.start(ZendaAdhoc.step(.breathe, minutes: value, in: routines), source: "start")
            }
        }
    }

    private func scan(_ routines: [ScheduleRoutine]) -> some View {
        tile(ZendaStepKind.scan.symbol, "Body scan") {
            minutes([5, 10, 20], usual: ZendaAdhoc.minutes(.scan, in: routines) ?? 10) { value in
                ZendaAdhoc.start(ZendaAdhoc.step(.scan, minutes: value, in: routines), source: "start")
            }
        }
    }

    private func projectTile(_ name: String, _ kind: ZendaAdhoc.Kind, choices: [Int], selection: Binding<String?>, fallback: String?,
                             list: [ZendaProject], routines: [ScheduleRoutine]) -> some View {
        let chosen = list.first { $0.id == selection.wrappedValue }?.id ?? fallback
        let pool = list.first { $0.id == chosen }.map { p in routines.filter { $0.id.uuidString == p.routine } } ?? routines
        let symbol = kind.isSay ? ZendaStepKind.say.symbol : ZendaStepKind.visualize.symbol
        return tile(symbol, name) {
            HStack(spacing: 6) {
                ForEach(list) { project in
                    Button(project.name) { selection.wrappedValue = project.id }
                        .buttonStyle(ZendaChip(on: project.id == chosen))
                }
            }
            minutes(choices, usual: ZendaAdhoc.minutes(kind, in: pool)) { value in
                ZendaAdhoc.start(ZendaAdhoc.step(kind, minutes: value, in: pool.isEmpty ? routines : pool), source: "start")
            }
        }
    }

    private func journal(_ routines: [ScheduleRoutine]) -> some View {
        let books = ZendaBooks.all.filter { $0.tag != "note" }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                icon(ZendaStepKind.write.symbol)
                Text("Journal").font(Zen.round(19, .bold))
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ForEach(Array(books.enumerated()), id: \.offset) { index, book in
                    Button { ZendaAdhoc.start(ZendaAdhoc.step(.write(book.tag), minutes: nil, in: routines), source: "start") } label: {
                        ZendaSpineCover(title: book.name, style: index % 3)
                    }
                    .buttonStyle(.plain)
                }
                Button { ZendaAdhoc.start(ZendaAdhoc.step(.write("note"), minutes: nil, in: routines), source: "start") } label: {
                    ZendaSpineCover(title: "Blank", style: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .zendaCard(24)
    }
}

extension ZendaAdhoc.Kind {
    var isSay: Bool { if case .say = self { return true }; return false }
}

struct ZendaSpineCover: View {
    let title: String
    let style: Int

    var body: some View {
        let dark = style < 2
        VStack(alignment: .leading) {
            Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(title).font(Zen.round(13, .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(dark ? Zen.paper : Zen.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 92)
        .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 14, topTrailingRadius: 14)
            .fill(style == 0 ? Zen.ink : style == 1 ? Zen.umber : Zen.pale))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 14, topTrailingRadius: 14)
            .stroke(Zen.ink, style: StrokeStyle(lineWidth: dark ? 0 : 1.5, dash: style == 3 ? [5, 4] : [])))
        .contentShape(Rectangle())
    }
}
