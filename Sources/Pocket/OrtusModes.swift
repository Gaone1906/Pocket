import AppKit
import SwiftUI

extension Fab {
    static let dim = Color(hex: 0x6B5246)
}

extension FabulaFilm {
    var byline: String {
        [year.map { String($0) } ?? "", director].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var cardURL: URL? { FabulaFormat.poster(poster, size: "w342") }
}

struct FabulaFlow: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

struct FabulaPulse: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.4 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

struct FabulaChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Fab.sans(13, .semibold))
                .foregroundStyle(on ? Fab.onAccent : Fab.muted)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(on ? Fab.accent : Fab.surface))
                .overlay(Capsule().stroke(on ? Fab.accent : Fab.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FabulaKicker: View {
    let text: String
    var color: Color = Fab.faint

    var body: some View {
        Text(text.uppercased()).font(Fab.sans(11, .bold)).tracking(1.2).foregroundStyle(color)
    }
}

struct FabulaScoreBar: View {
    let value: Int?
    let set: (Int) -> Void

    let knob: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let span = max(1, geo.size.width - knob)
            let x = CGFloat(Double((value ?? 5) - 1) / 9) * span
            ZStack(alignment: .leading) {
                Capsule().fill(Fab.line).frame(height: 6)
                if value != nil {
                    Capsule().fill(Fab.accent).frame(width: x + knob / 2, height: 6)
                }
                Circle()
                    .fill(value == nil ? Fab.surface : Fab.ink)
                    .overlay(Circle().stroke(value == nil ? Fab.dim : Fab.accent, lineWidth: 3))
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let ratio = min(1, max(0, (drag.location.x - knob / 2) / span))
                        set(Int((ratio * 9).rounded()) + 1)
                    }
            )
        }
        .frame(height: 28)
    }
}

struct FabulaRefinerView: View {
    @ObservedObject var refiner: FabulaRefiner
    @ObservedObject var nav: FabulaNav

    var body: some View {
        Group {
            switch refiner.stage {
            case .pick: FabulaRefinerPick(refiner: refiner)
            case .list: FabulaRefinerList(refiner: refiner)
            case .done: FabulaRefinerDone(refiner: refiner, nav: nav)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FabulaRefinerPick: View {
    @ObservedObject var refiner: FabulaRefiner

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What would you like to refine?").font(Fab.serif(28))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    group("Language", options: FabulaRefiner.languages, chosen: refiner.langs) { refiner.toggleLang($0) }
                    group("Genre", options: FabulaRefiner.genres, chosen: refiner.genres) { refiner.toggleGenre($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            FabulaButton(title: "Start refining", filled: true, height: 50) { refiner.begin() }
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 28)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private func group(_ word: String, options: [String], chosen: [String], toggle: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FabulaKicker(text: word)
            FabulaFlow(spacing: 8) {
                FabulaChip(title: "Any", on: chosen.isEmpty) { toggle(nil) }
                ForEach(options, id: \.self) { name in
                    FabulaChip(title: name, on: chosen.contains(name)) { toggle(name) }
                }
            }
        }
    }
}

struct FabulaRefinerList: View {
    @ObservedObject var refiner: FabulaRefiner

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 30)
                .padding(.bottom, 14)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Fab.line).frame(height: 1)
            ScrollView {
                VStack(spacing: 12) {
                    if refiner.loading {
                        ForEach(0..<5, id: \.self) { _ in placeholder }
                    } else {
                        ForEach(refiner.films) { film in row(film) }
                        if let problem = refiner.problem {
                            HStack(spacing: 12) {
                                Text(problem).font(Fab.sans(12.5)).foregroundStyle(Fab.faint)
                                if refiner.films.isEmpty {
                                    FabulaSmallButton(title: "Retry") { refiner.retry() }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                        }
                        buttons.padding(.top, 8)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 26)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Refiner").font(Fab.serif(24))
                Text(refiner.choice).font(Fab.sans(12.5)).foregroundStyle(Fab.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(refiner.total) rated")
                .font(Fab.sans(13, .semibold))
                .foregroundStyle(Fab.washText)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Fab.wash))
        }
    }

    private func row(_ film: FabulaFilm) -> some View {
        let value = refiner.scores[film.tmdb]
        return HStack(alignment: .top, spacing: 14) {
            FabulaPoster(url: film.cardURL, radius: 10).frame(width: 70, height: 105)
            VStack(alignment: .leading, spacing: 4) {
                Text(film.title).font(Fab.serif(17)).foregroundStyle(Fab.ink).lineLimit(2)
                if !film.byline.isEmpty {
                    Text(film.byline).font(Fab.sans(12)).foregroundStyle(Fab.muted).lineLimit(1)
                }
                if !film.overview.isEmpty {
                    Text(film.overview).font(Fab.sans(13)).foregroundStyle(Fab.ink).lineSpacing(2).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    FabulaScoreBar(value: value) { refiner.score(film.tmdb, $0) }
                    Text(value.map { "\($0) / 10" } ?? "Not seen")
                        .font(Fab.sans(13, .semibold))
                        .foregroundStyle(value == nil ? Fab.faint : Fab.washText)
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Fab.line, lineWidth: 1))
    }

    private var placeholder: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fab.wash).frame(width: 70, height: 105)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Fab.line).frame(width: 180, height: 14)
                Capsule().fill(Fab.line).frame(width: 110, height: 10)
                Capsule().fill(Fab.line).frame(height: 10)
                Capsule().fill(Fab.line).frame(width: 260, height: 10)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Fab.line, lineWidth: 1))
        .modifier(FabulaPulse())
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            FabulaButton(title: "Stop", color: Fab.muted, height: 48) { refiner.stop() }
                .frame(width: 200)
            FabulaButton(title: "Continue: 10 more", filled: true, height: 48) { refiner.next() }
                .disabled(refiner.films.isEmpty)
                .opacity(refiner.films.isEmpty ? 0.5 : 1)
        }
    }
}

struct FabulaRefinerDone: View {
    @ObservedObject var refiner: FabulaRefiner
    @ObservedObject var nav: FabulaNav

    private var counts: String {
        "\(refiner.rated) \(refiner.rated == 1 ? "film" : "films") rated, \(refiner.skipped) not seen."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Fab.accent)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Fab.wash))
                    Text("Taste updated").font(Fab.serif(28))
                    Text(counts).font(Fab.sans(14)).foregroundStyle(Fab.muted)
                }
                .frame(maxWidth: .infinity)
                if refiner.tasting {
                    loadingCards
                } else if let taste = refiner.taste {
                    if !taste.more.isEmpty || !taste.less.isEmpty { changed(taste) }
                    if !taste.summary.isEmpty { summary(taste.summary) }
                } else if let problem = refiner.tasteProblem {
                    Text(problem).font(Fab.sans(12.5)).foregroundStyle(Fab.faint)
                }
                VStack(spacing: 6) {
                    FabulaButton(title: "Back to Recommend", filled: true, height: 50) {
                        nav.tab = .recommend
                        note("fabula tab changed tab=recommend source=refiner done")
                        refiner.again()
                    }
                    Button { refiner.again() } label: {
                        Text("Refine something else")
                            .font(Fab.sans(14, .semibold))
                            .foregroundStyle(Fab.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 28)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func changed(_ taste: FabulaTaste) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FabulaKicker(text: "What changed")
            ForEach(Array(taste.more.enumerated()), id: \.offset) { _, label in
                line(label, mark: "↑ more", color: Fab.yes)
            }
            ForEach(Array(taste.less.enumerated()), id: \.offset) { _, label in
                line(label, mark: "↓ less", color: Fab.no)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Fab.line, lineWidth: 1))
    }

    private func line(_ label: String, mark: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Fab.sans(14)).foregroundStyle(Fab.ink)
            Spacer(minLength: 8)
            Text(mark).font(Fab.sans(14, .semibold)).foregroundStyle(color)
        }
    }

    private func summary(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FabulaKicker(text: "Your taste, in a line", color: Fab.washText)
            Text(text).font(Fab.serif(17, .semibold)).foregroundStyle(Fab.ink).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fab.wash))
    }

    private var loadingCards: some View {
        VStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                FabulaKicker(text: "What changed")
                ForEach(0..<3, id: \.self) { index in
                    HStack {
                        Capsule().fill(Fab.line).frame(width: CGFloat(170 - index * 30), height: 11)
                        Spacer()
                        Capsule().fill(Fab.line).frame(width: 60, height: 11)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fab.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Fab.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 10) {
                FabulaKicker(text: "Your taste, in a line", color: Fab.washText)
                Capsule().fill(Fab.washText.opacity(0.25)).frame(height: 12)
                Capsule().fill(Fab.washText.opacity(0.25)).frame(width: 280, height: 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fab.wash))
        }
        .modifier(FabulaPulse())
    }
}

struct FabulaAIView: View {
    @ObservedObject var ai: FabulaAI

    var body: some View {
        Group {
            if ai.active {
                FabulaAIResults(ai: ai)
            } else {
                FabulaAIMood(ai: ai)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FabulaAIMood: View {
    @ObservedObject var ai: FabulaAI

    private var empty: Bool { ai.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Fab.accent)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Fab.wash))
                Text("What are you in the mood for?").font(Fab.serif(28)).multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                ForEach(FabulaAI.ideas, id: \.self) { idea in
                    Button { ai.mood = idea } label: {
                        Text(idea)
                            .font(Fab.sans(13, .medium))
                            .foregroundStyle(Fab.muted)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(Fab.surface))
                            .overlay(Capsule().stroke(Fab.line, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                FabulaKicker(text: "Your mood")
                TextField("Rainy Sunday, want something cosy but not dumb, under 2 hours", text: $ai.mood, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Fab.sans(16))
                    .foregroundStyle(Fab.ink)
                    .lineLimit(4...6)
                    .onSubmit { ai.find() }
                Button { ai.find() } label: {
                    HStack(spacing: 8) {
                        Text("Find films")
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                    }
                    .font(Fab.sans(15, .bold))
                    .foregroundStyle(Fab.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(empty)
                .opacity(empty ? 0.5 : 1)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fab.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Fab.line, lineWidth: 1))
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 28)
        .frame(maxWidth: 660, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadialGradient(colors: [Fab.wash, Fab.ground], center: .top, startRadius: 0, endRadius: 560))
    }
}

struct FabulaAIResults: View {
    @ObservedObject var ai: FabulaAI

    private static let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 30)
                .padding(.bottom, 14)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Fab.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Self.columns, spacing: 14) {
                        if ai.loading {
                            ForEach(0..<4, id: \.self) { _ in placeholder }
                        } else {
                            ForEach(ai.films) { film in card(film) }
                        }
                    }
                    if let problem = ai.problem, !ai.loading {
                        Text(problem).font(Fab.sans(12.5)).foregroundStyle(Fab.faint)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            Rectangle().fill(Fab.line).frame(height: 1)
            bar
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .background(Fab.raised)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { ai.leave() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Fab.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Fab.surface))
                        .overlay(Circle().stroke(Fab.line, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Change mood")
                Text("AI Mode").font(Fab.serif(24))
                Spacer()
                Text("Round \(max(1, ai.round))").font(Fab.sans(12.5)).foregroundStyle(Fab.faint)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(ai.thread.suffix(2).enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(Fab.sans(13))
                        .foregroundStyle(Fab.washText)
                        .lineLimit(3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fab.wash))
                }
            }
        }
    }

    private func card(_ film: FabulaFilm) -> some View {
        let on = ai.chosen == film.tmdb
        return HStack(alignment: .top, spacing: 12) {
            FabulaPoster(url: film.cardURL, radius: 10).frame(width: 76, height: 114)
            VStack(alignment: .leading, spacing: 4) {
                Text(film.title).font(Fab.serif(17)).foregroundStyle(Fab.ink).lineLimit(1)
                Text(film.credits).font(Fab.sans(12)).foregroundStyle(Fab.muted).lineLimit(1)
                if !film.why.isEmpty {
                    Text(film.why).font(Fab.sans(13)).foregroundStyle(Fab.ink).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button { ai.choose(film) } label: {
                    Text(on ? "Chosen" : "This one")
                        .font(Fab.sans(13, .bold))
                        .foregroundStyle(on ? Fab.onGold : Fab.washText)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(on ? Fab.gold : Fab.wash))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(height: 166)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Fab.gold : Fab.line, lineWidth: on ? 2 : 1))
    }

    private var placeholder: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fab.wash).frame(width: 76, height: 114)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Fab.line).frame(width: 150, height: 14)
                Capsule().fill(Fab.line).frame(width: 110, height: 10)
                Capsule().fill(Fab.line).frame(height: 10)
                Capsule().fill(Fab.line).frame(width: 120, height: 10)
                Spacer(minLength: 4)
                Capsule().fill(Fab.wash).frame(width: 84, height: 32)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(height: 166)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Fab.line, lineWidth: 1))
        .modifier(FabulaPulse())
    }

    private var bar: some View {
        VStack(spacing: 10) {
            if let pick = ai.pick {
                Button { ai.watch(source: "ai") } label: {
                    Text("Watch \(pick.title) tonight")
                        .font(Fab.sans(15, .bold))
                        .foregroundStyle(Fab.onGold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.gold))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                TextField("Less animation, more like Knives Out", text: $ai.tune)
                    .textFieldStyle(.plain)
                    .font(Fab.sans(14.5))
                    .foregroundStyle(Fab.ink)
                    .onSubmit { ai.send() }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Fab.line, lineWidth: 1))
                Button { ai.send() } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Fab.onAccent)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(ai.loading)
                .opacity(ai.loading ? 0.5 : 1)
            }
            Button { ai.reject() } label: {
                Text("None of these, try again")
                    .font(Fab.sans(14, .semibold))
                    .foregroundStyle(Fab.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Fab.line, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ai.loading)
            .opacity(ai.loading ? 0.5 : 1)
        }
    }
}
