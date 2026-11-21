import SwiftUI

enum ZendaSessions {
    static func start(_ session: KairosSession, source: String) {
        KairosRunner.zenda.start(session)
        note("zenda session started adhoc=false source=\(source) routine=\(session.routine.name) day=\(session.day) slot=\(session.slot.rawValue) steps=\(session.total) done=\(session.done)")
    }

    static func hour(_ value: Int) -> String { String(format: "%02d:00", value) }
}

struct ZendaStepRow: View {
    let step: ScheduleStep
    var height: CGFloat = 46
    var size: CGFloat = 16
    var struck = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: ZendaRoutines.kind(step).symbol)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 20)
            Text(ZendaRoutines.name(step))
                .font(Zen.round(size))
                .strikethrough(struck, color: Zen.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(ZendaRoutines.minutes(step))")
                .font(Zen.round(13, .bold))
                .foregroundStyle(Zen.muted)
        }
        .frame(height: height)
    }
}

struct ZendaHalfDot: View {
    let done: Int
    let total: Int
    var side: CGFloat = 26

    var body: some View {
        ZStack {
            if total > 0 && done >= total {
                Circle().fill(Zen.ink)
            } else if done > 0 {
                Circle().fill(Zen.stone)
                Circle().fill(Zen.ink).mask(HStack(spacing: 0) { Rectangle(); Color.clear })
            } else {
                Circle().strokeBorder(Zen.stone, lineWidth: 2)
            }
        }
        .frame(width: side, height: side)
    }
}

struct ZendaToday: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var projects: ZendaStore
    @ObservedObject var runner: KairosRunner

    var body: some View {
        let today = store.today
        let ledger = ZendaLedger(store)
        let sessions = ledger.sessions(on: today)
        let open = sessions.filter { !$0.finished }
        let next = open.first { $0.slot == store.slotNow } ?? open.first
        let applying = projects.applying(on: today)
        VStack(alignment: .leading, spacing: 26) {
            header(today, streak: ledger.streak(today: today))
            if sessions.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "leaf").font(.system(size: 54, weight: .light)).opacity(0.25)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 22, alignment: .top), GridItem(.flexible(), spacing: 22, alignment: .top)], alignment: .leading, spacing: 22) {
                        ForEach(sessions) { session in
                            card(session, next: session.id == next?.id, projects: applying.filter { $0.routine == session.routine.id.uuidString })
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
            week(today, ledger: ledger, applying: applying)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            ZendaEnso().frame(width: 300, height: 300).opacity(0.08).offset(x: 50, y: -70)
        }
        .clipped()
    }

    private func header(_ today: String, streak: Int) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            Text(ZendaDates.format(today, "EEEE")).font(Zen.serif(40, .bold)).lineLimit(1)
            Text(ZendaDates.format(today, "d MMM")).font(Zen.round(18, .bold)).foregroundStyle(Zen.muted).padding(.bottom, 4)
            Text("禅")
                .font(Zen.serif(17, .medium))
                .foregroundStyle(Zen.paper)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Zen.vermilion))
                .padding(.bottom, 3)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "flame").font(.system(size: 17, weight: .medium))
                Text("\(streak)").font(Zen.round(17, .bold)).monospacedDigit()
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .overlay(Capsule().strokeBorder(Zen.ink, lineWidth: 1.5))
        }
    }

    private func card(_ session: KairosSession, next: Bool, projects: [ZendaProject]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: session.slot.symbol).font(.system(size: 17, weight: .regular)).frame(width: 20)
                Text(session.slot.label).font(Zen.serif(20, .bold))
                ForEach(projects) { project in
                    Text(project.name)
                        .font(Zen.round(12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 110)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Zen.pale))
                }
                Spacer(minLength: 6)
                if session.finished {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Zen.paper)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Zen.ink))
                } else {
                    Text(ZendaSessions.hour(session.slot == .morning ? store.book.dayFrom : store.book.nightFrom))
                        .font(Zen.round(14))
                        .foregroundStyle(Zen.muted)
                }
            }
            .padding(.bottom, 10)
            ForEach(Array(session.steps.enumerated()), id: \.offset) { index, step in
                ZendaStepRow(step: step, struck: session.finished)
                if index < session.steps.count - 1 { Rectangle().fill(Zen.rule).frame(height: 1) }
            }
            if next {
                Button { ZendaSessions.start(session, source: "today") } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 16))
                        Text(session.done > 0 ? "Resume · \(KairosPlan.minutes(session.seconds)) min" : "Start · \(KairosPlan.minutes(session.seconds)) min")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ZendaFilled())
                .keyboardShortcut(.return, modifiers: [])
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .zendaCard(22, stroke: next ? Zen.ink : Zen.line, width: next ? 1.5 : 1)
        .opacity(session.finished ? 0.55 : 1)
    }

    private func week(_ today: String, ledger: ZendaLedger, applying: [ZendaProject]) -> some View {
        let monday = ZendaDates.monday(today)
        return HStack(spacing: 22) {
            ForEach(0..<7, id: \.self) { offset in
                let day = ScheduleDays.shift(monday, by: offset)
                let fill = ledger.fill(on: day)
                let isToday = day == today
                VStack(spacing: 8) {
                    Text(ZendaDates.format(day, "EEEEE"))
                        .font(Zen.round(12, isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Zen.ink : Zen.muted)
                    ZendaHalfDot(done: fill.done, total: fill.total)
                        .overlay(Circle().stroke(isToday ? Zen.ink : Color.clear, lineWidth: 2).padding(-4))
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                ForEach(applying) { project in
                    ZendaPill(text: "\(project.name) · day \(project.dayNumber(today))", symbol: "scope")
                        .frame(maxWidth: 200)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Zen.line, lineWidth: 1))
    }
}
