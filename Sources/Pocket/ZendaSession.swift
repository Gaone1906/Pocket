import SwiftUI

struct ZendaSessionView: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let state: KairosRunState
    @State private var hideLines = false

    private var beat: KairosBeat { live.beat ?? live.beats[0] }

    var body: some View {
        VStack(spacing: 0) {
            top
            if state.finished != nil {
                finished
            } else if state.waiting {
                waiting
            } else {
                stage.id(live.index)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 40)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var top: some View {
        HStack(spacing: 22) {
            Spacer().frame(width: 50)
            Button { runner.end(reason: state.finished == nil ? "close" : "finished") } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(ZendaCircleButton(side: 40, stroke: Zen.edge))
            .keyboardShortcut(.cancelAction)
            HStack(spacing: 10) {
                ForEach(Array(live.steps.enumerated()), id: \.offset) { index, step in
                    segment(index, step)
                }
            }
            Text(state.finished != nil ? KairosPlan.clock(0) : left >= 1 ? KairosPlan.clock(left) : "\(beat.step + 1) / \(live.steps.count)")
                .font(Zen.round(18, .bold))
                .monospacedDigit()
        }
    }

    private var left: Double {
        let later = live.steps.indices.filter { $0 > beat.step }.reduce(0) { $0 + KairosPlan.estimate(live.steps[$1]) }
        let now = beat.counted ? runner.remaining : Double(KairosPlan.estimate(live.steps[beat.step]))
        return max(runner.sessionLeft(live), Double(later) + now)
    }

    private func segment(_ index: Int, _ step: ScheduleStep) -> some View {
        let current = state.finished == nil ? beat.step : live.steps.count
        let fill: CGFloat = index < current ? 1 : index > current ? 0 : max(0.03, progress)
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: ZendaRoutines.kind(step).symbol).font(.system(size: 15, weight: .regular)).frame(height: 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Zen.line)
                    Capsule().fill(Zen.ink).frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .opacity(index == current ? 1 : index < current ? 0.45 : 0.4)
        .help(ZendaRoutines.name(step))
    }

    private var progress: CGFloat {
        let inStep = live.beats.enumerated().filter { $0.element.step == beat.step }
        let position = CGFloat(inStep.firstIndex { $0.offset == live.index } ?? 0)
        let count = CGFloat(max(1, inStep.count))
        var part: CGFloat = 0
        if beat.counted, beat.seconds > 0 {
            part = CGFloat(1 - runner.remaining / Double(beat.seconds))
        } else if beat.kind == .say {
            part = CGFloat(state.sayLine) / CGFloat(max(1, beat.lines.isEmpty ? 1 : beat.lines.count))
        } else if let soft = runner.softLeft(beat), beat.guide > 0 {
            part = CGFloat(1 - soft / Double(beat.guide))
        }
        return (position + min(1, max(0, part))) / count
    }

    @ViewBuilder private var stage: some View {
        switch beat.kind {
        case .count, .rest:
            if !beat.box.isEmpty {
                ZendaBreathe(runner: runner, beat: beat, state: state)
            } else if !beat.reads.isEmpty {
                ZendaVisualize(runner: runner, beat: beat, state: state, hidden: $hideLines)
            } else {
                ZendaTimer(runner: runner, beat: beat, state: state)
            }
        case .say: ZendaAffirm(runner: runner, beat: beat, state: state)
        case .write: ZendaJournalPage(runner: runner, journal: journal, live: live, beat: beat, state: state)
        case .reps, .log: tap
        }
    }

    private var tap: some View {
        VStack(spacing: 26) {
            Spacer()
            Text(beat.name).font(Zen.serif(40, .medium)).multilineTextAlignment(.center)
            if !beat.tip.isEmpty {
                Text(beat.tip).font(Zen.round(15)).foregroundStyle(Zen.muted).multilineTextAlignment(.center).frame(maxWidth: 560).lineLimit(5)
            }
            Button { runner.advance() } label: {
                HStack(spacing: 10) { Image(systemName: "checkmark"); Text("Done") }
            }
            .buttonStyle(ZendaFilled(height: 60, size: 18))
            .keyboardShortcut(.return, modifiers: [])
            Spacer()
        }
    }

    private var waiting: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: ZendaRoutines.kind(live.steps[beat.step]).symbol).font(.system(size: 34, weight: .light))
            Text(beat.name).font(Zen.serif(40, .medium))
            Button { runner.togglePause() } label: {
                HStack(spacing: 10) { Image(systemName: "play.fill"); Text("Start") }
            }
            .buttonStyle(ZendaFilled(height: 60, size: 18))
            .keyboardShortcut(.return, modifiers: [])
            Spacer()
        }
    }

    private var finished: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                ZendaEnso().frame(width: 260, height: 260).opacity(0.13)
                Image(systemName: "checkmark").font(.system(size: 44, weight: .semibold))
            }
            Text(state.adhocName.map { _ in ZendaRoutines.name(live.steps[0]) } ?? live.routine.name).font(Zen.serif(34, .medium))
            Text("\(KairosPlan.minutes(Int((state.finished ?? Date()).timeIntervalSince(state.started)))) min")
                .font(Zen.round(15)).foregroundStyle(Zen.muted)
            Button("Close") { runner.end(reason: "finished") }
                .buttonStyle(ZendaFilled(height: 52, fill: Zen.ink))
                .keyboardShortcut(.return, modifiers: [])
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ZendaControls: View {
    @ObservedObject var runner: KairosRunner
    let paused: Bool
    var bigPause = true
    var leading: AnyView? = nil

    var body: some View {
        HStack(spacing: 18) {
            if let leading { leading }
            Button { runner.togglePause() } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: bigPause ? 24 : 20, weight: .semibold))
            }
            .buttonStyle(ZendaCircleButton(side: bigPause ? 64 : 52, filled: bigPause, stroke: Zen.stone))
            .keyboardShortcut(.space, modifiers: [])
            Button { runner.advance() } label: {
                Image(systemName: "forward.end").font(.system(size: 20, weight: .medium))
            }
            .buttonStyle(ZendaCircleButton(side: 52, stroke: bigPause ? Zen.ink : Zen.stone))
        }
    }
}

struct ZendaBreathe: View {
    @ObservedObject var runner: KairosRunner
    let beat: KairosBeat
    let state: KairosRunState

    private static let corners: [CGPoint] = [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]
    private static let labels = ["In", "Hold", "Out", "Hold"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.paused || state.endsAt == nil)) { context in
                let left = state.endsAt.map { max(0, $0.timeIntervalSince(context.date)) } ?? (state.left ?? 0)
                let breath = KairosPlan.breath(beat.box, max(0, Double(beat.seconds) - left))
                VStack(spacing: 34) {
                    square(breath)
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule().fill(index == breath.index ? Zen.ink : Zen.stone).frame(width: 34, height: 6)
                        }
                    }
                }
            }
            Spacer()
            ZendaControls(runner: runner, paused: state.paused)
        }
    }

    private func square(_ breath: KairosBreath) -> some View {
        let side: CGFloat = 300
        let from = Self.corners[breath.index]
        let to = Self.corners[(breath.index + 1) % 4]
        let point = CGPoint(x: (from.x + (to.x - from.x) * breath.fraction) * side, y: (from.y + (to.y - from.y) * breath.fraction) * side)
        return ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Zen.ink, lineWidth: 3)
            VStack(spacing: 0) {
                Text(Self.labels[breath.index]).font(Zen.round(22)).foregroundStyle(Zen.muted)
                Text("\(breath.left)").font(Zen.round(96, .bold)).monospacedDigit()
            }
            Circle().fill(Zen.vermilion).frame(width: 22, height: 22).position(point)
        }
        .frame(width: side, height: side)
    }
}

struct ZendaVisualize: View {
    @ObservedObject var runner: KairosRunner
    let beat: KairosBeat
    let state: KairosRunState
    @Binding var hidden: Bool

    var body: some View {
        let elapsed = max(0, Double(beat.seconds) - runner.remaining)
        let at = (Int(elapsed) / max(1, beat.every)) % max(1, beat.reads.count)
        let detail = KairosPlan.plainDetail(beat.detail)
        VStack(spacing: 0) {
            ZStack {
                ZendaEnso().frame(width: 470, height: 470).opacity(0.13)
                VStack(spacing: 22) {
                    Text((detail.isEmpty ? beat.name : detail).uppercased())
                        .font(Zen.round(14))
                        .kerning(3)
                        .foregroundStyle(Zen.muted)
                    Text(hidden ? " " : beat.reads[at])
                        .font(Zen.serif(34, .medium))
                        .lineSpacing(8)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        ForEach(0..<beat.reads.count, id: \.self) { index in
                            Circle()
                                .fill(index == at ? Zen.vermilion : Zen.ink.opacity(index < at ? 0.35 : 0.2))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                .frame(maxWidth: 560)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ZendaControls(runner: runner, paused: state.paused, leading: AnyView(
                Button { hidden.toggle() } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye").font(.system(size: 19, weight: .regular)).opacity(0.7)
                }
                .buttonStyle(ZendaCircleButton(side: 52, stroke: Zen.stone))
                .help(hidden ? "Show lines" : "Hide lines")
            ))
        }
    }
}

struct ZendaTimer: View {
    @ObservedObject var runner: KairosRunner
    let beat: KairosBeat
    let state: KairosRunState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ZendaEnso().frame(width: 470, height: 470).opacity(0.13)
                VStack(spacing: 18) {
                    Text(beat.name.uppercased()).font(Zen.round(14)).kerning(3).foregroundStyle(Zen.muted)
                    Text(KairosPlan.clock(runner.remaining)).font(Zen.round(96, .bold)).monospacedDigit()
                    if let cue = beat.cues.last(where: { Double($0.at) <= Double(beat.seconds) - runner.remaining }) {
                        Text(cue.text).font(Zen.serif(24, .medium)).multilineTextAlignment(.center).frame(maxWidth: 560)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ZendaControls(runner: runner, paused: state.paused)
        }
    }
}

struct ZendaAffirm: View {
    @ObservedObject var runner: KairosRunner
    let beat: KairosBeat
    let state: KairosRunState

    var body: some View {
        let lines = beat.lines.isEmpty ? [beat.name] : beat.lines
        let at = min(state.sayLine, lines.count - 1)
        VStack(spacing: 0) {
            VStack(spacing: 30) {
                Spacer()
                Text("\(at + 1) / \(lines.count)").font(Zen.round(14)).kerning(3).foregroundStyle(Zen.muted)
                Text(lines[at])
                    .font(Zen.serif(40, .medium))
                    .lineSpacing(10)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
                    .fixedSize(horizontal: false, vertical: true)
                ZendaBrush().fill(Zen.ink.opacity(0.18)).frame(width: 260, height: 14)
                HStack(spacing: 8) {
                    ForEach(0..<max(1, beat.times), id: \.self) { index in
                        Circle()
                            .fill(index < state.said ? Zen.vermilion : Color.clear)
                            .overlay(Circle().stroke(Zen.vermilion, lineWidth: 1.5))
                            .frame(width: 12, height: 12)
                    }
                }
                Button { runner.said() } label: {
                    HStack(spacing: 10) { Image(systemName: "checkmark"); Text("Said it") }
                }
                .buttonStyle(ZendaFilled(height: 60, size: 18))
                .keyboardShortcut(.return, modifiers: [])
                Spacer()
            }
            .frame(maxWidth: .infinity)
            ZendaControls(runner: runner, paused: state.paused, bigPause: false)
        }
    }
}

struct ZendaBrush: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 260, sy = rect.height / 14
        var path = Path()
        path.move(to: CGPoint(x: 4 * sx, y: 9 * sy))
        path.addCurve(to: CGPoint(x: 256 * sx, y: 6 * sy), control1: CGPoint(x: 60 * sx, y: 3 * sy), control2: CGPoint(x: 170 * sx, y: 2 * sy))
        path.addCurve(to: CGPoint(x: 10 * sx, y: 13 * sy), control1: CGPoint(x: 190 * sx, y: 9 * sy), control2: CGPoint(x: 90 * sx, y: 12 * sy))
        path.closeSubpath()
        return path
    }
}

struct ZendaJournalPage: View {
    @ObservedObject var runner: KairosRunner
    @ObservedObject var journal: KairosJournal
    let live: KairosLive
    let beat: KairosBeat
    let state: KairosRunState
    @State private var lines: [String] = []
    @State private var text = ""
    @State private var loaded = false
    @State private var pending: DispatchWorkItem?
    @State private var showBook = false

    private var step: ScheduleStep { live.steps[beat.step] }

    private var base: KairosEntry {
        let split = KairosPlan.split(step.title)
        let title = [split.name, KairosPlan.plainDetail(split.detail)].filter { !$0.isEmpty }.joined(separator: " · ")
        return KairosEntry(id: KairosEntry.id(routine: live.routine.id, day: state.day, slot: state.slot, step: step.id.uuidString),
                           routine: live.routine.id.uuidString, routineName: live.routine.name, day: state.day, slot: state.slot.rawValue,
                           step: step.id.uuidString, title: title, tag: beat.tag)
    }

    private var rows: Int { beat.fields > 1 ? beat.fields : 0 }

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)
            HStack(spacing: 14) {
                Button { store(); showBook = true } label: {
                    Image(systemName: "book.closed").font(.system(size: 19, weight: .regular))
                }
                .buttonStyle(ZendaCircleButton(side: 52, stroke: Zen.stone))
                .help("Open the \(ZendaBooks.name(beat.tag)) book")
                Button {
                    store()
                    note("zenda journal saved tag=\(beat.tag) day=\(state.day) slot=\(state.slot.rawValue) adhoc=\(state.adhoc != nil)")
                    runner.advance()
                } label: {
                    HStack(spacing: 12) {
                        Text("Save")
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                        Text("⌘↩").font(Zen.round(13)).opacity(0.8)
                    }
                }
                .buttonStyle(ZendaFilled(height: 56))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: store)
        .sheet(isPresented: $showBook) {
            ZendaBookView(journal: journal, projects: ZendaStore.shared, tag: ZendaBooks.tags.contains(beat.tag) ? beat.tag : "note", back: { showBook = false })
                .frame(width: 1000, height: 640)
                .background(ZendaBackdrop())
                .environment(\.colorScheme, .light)
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed").font(.system(size: 19, weight: .regular))
                Text(ZendaBooks.tags.contains(beat.tag) && beat.tag != "note" ? ZendaBooks.name(beat.tag) : beat.name).font(Zen.serif(30, .semibold))
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: state.slot.symbol).font(.system(size: 14))
                    Text(ZendaDates.format(state.day, "EEE d MMM"))
                }
                .font(Zen.round(14))
                .foregroundStyle(Zen.muted)
            }
            .padding(.bottom, 10)
            if !beat.prompt.isEmpty {
                Text(beat.prompt).font(Zen.round(13)).foregroundStyle(Zen.muted).lineLimit(3).padding(.bottom, 4)
            }
            if rows > 0 {
                ForEach(0..<rows, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("\(index + 1)").font(Zen.round(13)).foregroundStyle(Zen.muted).frame(width: 14, alignment: .leading)
                        TextField("", text: binding(index))
                            .textFieldStyle(.plain)
                            .font(Zen.serif(21, .regular))
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE6E0D3)).frame(height: 1) }
                }
            } else {
                TextEditor(text: $text)
                    .font(Zen.serif(21, .regular))
                    .scrollContentBackground(.hidden)
                    .lineSpacing(10)
                    .frame(minHeight: 160)
                    .onChange(of: text) { _, _ in later() }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 34)
        .padding(.bottom, 30)
        .frame(width: 660)
        .background(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18).fill(Zen.leaf)
            .shadow(color: Zen.ink.opacity(0.08), radius: 22, y: 22))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18).strokeBorder(Zen.line, lineWidth: 1))
        .background(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 0, topTrailingRadius: 0).fill(Zen.ink).frame(width: 12).offset(x: -5)
        }
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { lines.indices.contains(index) ? lines[index] : "" },
            set: { value in
                while lines.count <= index { lines.append("") }
                lines[index] = value
                later()
            }
        )
    }

    private func load() {
        guard !loaded else { return }
        let saved = journal.entry(base.id)
        lines = (0..<rows).map { index in
            let old = saved?.lines ?? []
            return old.indices.contains(index) ? old[index] : ""
        }
        text = saved?.text ?? ""
        loaded = true
    }

    private func later() {
        pending?.cancel()
        let work = DispatchWorkItem { store() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func store() {
        pending?.cancel()
        guard loaded else { return }
        var entry = journal.entry(base.id) ?? base
        if rows > 0 {
            let trimmed = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard trimmed.contains(where: { !$0.isEmpty }) || journal.entry(base.id) != nil else { return }
            entry.lines = trimmed
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty || journal.entry(base.id) != nil else { return }
            entry.text = trimmed
        }
        entry.title = base.title
        entry.tag = base.tag
        journal.put(entry)
    }
}
