import SwiftUI

enum FabulaAINet {
    static func call(_ action: String, body: [String: Any], detail: @escaping (Any) -> String, done: @escaping (Result<Any, Error>) -> Void) {
        var payload = body
        payload["action"] = action
        let started = Date()
        FabulaNet.function("fabula-ai", body: payload) { result in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            switch result {
            case .success(let json):
                if let message = (json as? [String: Any])?["error"] as? String {
                    note("fabula-ai failed action=\(action) durationMs=\(ms) error=\(message) \(inputs(payload))")
                    done(.failure(FabulaFailure(message: message)))
                } else {
                    note("fabula-ai ok action=\(action) durationMs=\(ms) \(inputs(payload)) \(detail(json))")
                    done(.success(json))
                }
            case .failure(let error):
                note("fabula-ai failed action=\(action) durationMs=\(ms) error=\(error.localizedDescription) \(inputs(payload))")
                done(.failure(error))
            }
        }
    }

    static func films(_ json: Any) -> [FabulaFilm] {
        let list = (json as? [String: Any])?["films"] as? [Any] ?? []
        return list.compactMap { ($0 as? [String: Any]).flatMap(FabulaFilm.init) }
    }

    private static func inputs(_ body: [String: Any]) -> String {
        var parts: [String] = []
        for key in ["langs", "genres", "exclude", "rated", "unseen", "notes"] {
            if let list = body[key] as? [Any] { parts.append("\(key)=\(list.count)") }
        }
        if let text = body["text"] as? String { parts.append("textLength=\(text.count)") }
        return parts.joined(separator: " ")
    }
}

struct FabulaFlow: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 600, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        let laid = arrange(bounds.width, subviews)
        for (index, point) in laid.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: LayoutSubviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), points)
    }
}

struct FabulaChip: View {
    let title: String
    let on: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Text(title)
                .font(Fab.sans(13, .semibold))
                .foregroundStyle(on ? Fab.washText : Fab.muted)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(on ? Fab.wash : Fab.surface))
                .overlay(Capsule().stroke(on ? Fab.accent.opacity(0.7) : Fab.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

final class FabulaAIMode: ObservableObject {
    static let shared = FabulaAIMode()
    static let ideas = ["Cosy and clever", "Edge of my seat", "Make me cry", "Something weird"]

    @Published var text = ""
    @Published var fine = ""
    @Published private(set) var notes: [String] = []
    @Published private(set) var films: [FabulaFilm] = []
    @Published private(set) var round = 0
    @Published private(set) var shown: [Int] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published var chosen: FabulaFilm?

    private var ticket = 0

    private init() {}

    var started: Bool { round > 0 }
    var mood: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var conversation: [String] { Array(([mood] + notes).filter { !$0.isEmpty }.suffix(2)) }

    func find() {
        guard !mood.isEmpty, !loading else { return }
        notes = []
        shown = []
        round = 0
        films = []
        chosen = nil
        fetch(source: "find")
    }

    func refine(note newNote: String?) {
        guard !loading else { return }
        if let newNote, !newNote.isEmpty {
            notes.append(newNote)
            fine = ""
        }
        fetch(source: newNote == nil ? "retry" : "fine-tune")
    }

    func restart() {
        ticket += 1
        loading = false
        error = nil
        round = 0
        films = []
        shown = []
        notes = []
        chosen = nil
        fine = ""
    }

    func watch(_ film: FabulaFilm) {
        OrtusStore.shared.record(film, .superlike, source: "ai mode")
        FabulaDeck.shared.addTonight(film)
        FabulaNav.shared.pick = film
        note("fabula ai mode watch tmdb=\(film.tmdb) round=\(round) notes=\(notes.count)")
    }

    private func fetch(source: String) {
        guard FabulaNet.connected else {
            error = "Cloud isn't connected."
            note("fabula ai mode skipped reason=not connected source=\(source)")
            return
        }
        ticket += 1
        let mine = ticket
        loading = true
        error = nil
        let exclude = Array(Set(shown)).sorted()
        let body: [String: Any] = ["text": mood, "notes": notes, "exclude": exclude]
        FabulaAINet.call("mood", body: body, detail: { "films=\(FabulaAINet.films($0).count) round=\(self.round + 1) source=\(source)" }) { [weak self] result in
            guard let self, mine == self.ticket else { return }
            self.loading = false
            switch result {
            case .success(let json):
                let found = FabulaAINet.films(json)
                if found.isEmpty {
                    self.error = "No films came back. Try rewording the mood."
                    return
                }
                self.films = found
                self.chosen = nil
                self.round += 1
                self.shown.append(contentsOf: found.map(\.tmdb))
            case .failure(let failure):
                self.error = failure.localizedDescription
            }
        }
    }
}

struct FabulaAIView: View {
    @ObservedObject var nav: FabulaNav
    @ObservedObject private var model = FabulaAIMode.shared

    var body: some View {
        Group {
            if model.started { results } else { input }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Fab.ground)
    }

    private var input: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What are you in the mood for?").font(Fab.serif(30)).foregroundStyle(Fab.ink)
                Text("Describe it in your own words and Fabula picks four films.").font(Fab.sans(14)).foregroundStyle(Fab.muted)
                FabulaFlow {
                    ForEach(FabulaAIMode.ideas, id: \.self) { idea in
                        FabulaChip(title: idea, on: model.text == idea) { model.text = idea }
                    }
                }
                TextEditor(text: $model.text)
                    .font(Fab.sans(15))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(height: 150)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Fab.line, lineWidth: 1))
                if let error = model.error { Text(error).font(Fab.sans(12.5)).foregroundStyle(Fab.muted) }
                HStack(spacing: 12) {
                    FabulaButton(title: "Find films", filled: true, height: 44) { model.find() }
                        .frame(width: 200)
                        .opacity(model.mood.isEmpty || model.loading ? 0.45 : 1)
                        .disabled(model.mood.isEmpty || model.loading)
                    if model.loading { ProgressView().controlSize(.small) }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.conversation.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(Fab.sans(13))
                                    .foregroundStyle(Fab.washText)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.wash))
                            }
                        }
                        Spacer()
                        FabulaSmallButton(title: "New search", color: Fab.muted) { model.restart() }
                    }
                    Text("ROUND \(model.round)").font(Fab.sans(11, .bold)).tracking(1.4).foregroundStyle(Fab.gold)
                    if model.loading {
                        HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 320)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16, alignment: .top)], spacing: 16) {
                            ForEach(model.films) { film in card(film) }
                        }
                    }
                    if let error = model.error { Text(error).font(Fab.sans(12.5)).foregroundStyle(Fab.muted) }
                }
                .padding(32)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            bar
        }
    }

    private func card(_ film: FabulaFilm) -> some View {
        let on = model.chosen?.tmdb == film.tmdb
        return VStack(alignment: .leading, spacing: 8) {
            FabulaPoster(url: film.posterURL, radius: 10)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
            Text(film.title).font(Fab.serif(16)).foregroundStyle(Fab.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(film.credits).font(Fab.sans(11.5)).foregroundStyle(Fab.muted).lineLimit(2)
            if !film.why.isEmpty {
                Text(film.why).font(Fab.sans(12)).foregroundStyle(Fab.faint).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                model.chosen = on ? nil : film
            } label: {
                Text(on ? "Chosen" : "This one")
                    .font(Fab.sans(12.5, .semibold))
                    .foregroundStyle(on ? Fab.onGold : Fab.gold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Capsule().fill(on ? Fab.gold : Color.clear))
                    .overlay(Capsule().stroke(Fab.gold, lineWidth: 1.2))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Fab.gold : Fab.line, lineWidth: on ? 2.5 : 1))
    }

    private var bar: some View {
        VStack(spacing: 10) {
            if let film = model.chosen {
                FabulaButton(title: "Watch \(film.title) tonight", color: Fab.gold, filled: true, height: 42) { model.watch(film) }
                    .frame(maxWidth: 520)
            }
            HStack(spacing: 10) {
                TextField("Fine-tune: a bit shorter, less violent, older…", text: $model.fine)
                    .textFieldStyle(.plain)
                    .font(Fab.sans(13.5))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Capsule().fill(Fab.surface))
                    .overlay(Capsule().stroke(Fab.line, lineWidth: 1))
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Fab.onAccent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Fab.accent))
                        .opacity(canSend ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                FabulaSmallButton(title: "None of these, try again", color: Fab.muted) { model.refine(note: nil) }
                    .opacity(model.loading ? 0.4 : 1)
                    .disabled(model.loading)
            }
            .frame(maxWidth: 760)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Fab.rail)
        .overlay(alignment: .top) { Rectangle().fill(Fab.railLine).frame(height: 1) }
    }

    private var canSend: Bool {
        !model.loading && !model.fine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        model.refine(note: model.fine.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
