import SwiftUI

struct FabulaChange: Identifiable {
    let id = UUID()
    let label: String
    let up: Bool
    let strength: String
}

final class FabulaRefiner: ObservableObject {
    static let shared = FabulaRefiner()
    static let languages = ["English", "Hindi", "Telugu", "Tamil", "Malayalam", "Korean", "Japanese", "Spanish"]
    static let genres = ["Action", "Animation", "Comedy", "Crime", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-fi", "Thriller", "War"]

    enum Phase { case pick, list, done }

    @Published private(set) var phase: Phase = .pick
    @Published var langs: [String] = []
    @Published var genres: [String] = []
    @Published private(set) var films: [FabulaFilm] = []
    @Published private(set) var ratings: [Int: Double] = [:]
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var summary = ""
    @Published private(set) var changes: [FabulaChange] = []
    @Published private(set) var unseenCount = 0

    private var shown: [Int] = []
    private var catalogue: [Int: FabulaFilm] = [:]
    private var committed = Set<Int>()
    private var ticket = 0

    private init() {}

    var ratedCount: Int { ratings.count }

    var scope: String {
        [langs.isEmpty ? "Any language" : langs.joined(separator: ", "), genres.isEmpty ? "Any genre" : genres.joined(separator: ", ")].joined(separator: " · ")
    }

    func rate(_ film: FabulaFilm, _ value: Double) {
        ratings[film.tmdb] = value
    }

    func start() {
        ratings = [:]
        shown = []
        catalogue = [:]
        committed = []
        films = []
        fetch(source: "start")
    }

    func more() {
        commit(films)
        fetch(source: "continue")
    }

    func stop() {
        guard !loading else { return }
        commit(films)
        guard FabulaNet.connected else {
            error = "Cloud isn't connected."
            note("fabula refiner taste skipped reason=not connected")
            return
        }
        ticket += 1
        let mine = ticket
        loading = true
        error = nil
        let rated = ratings.keys.sorted().map { ["tmdb": $0, "rating": ratings[$0] ?? 0] as [String: Any] }
        let unseen = shown.filter { ratings[$0] == nil }
        let body: [String: Any] = ["rated": rated, "unseen": unseen]
        let count = rated.count
        FabulaAINet.call("taste", body: body, detail: { json in
            let list = (json as? [String: Any])?["changes"] as? [Any] ?? []
            return "rated=\(count) unseen=\(unseen.count) changes=\(list.count)"
        }) { [weak self] result in
            guard let self, mine == self.ticket else { return }
            self.loading = false
            switch result {
            case .success(let json):
                let info = json as? [String: Any] ?? [:]
                self.summary = FabulaLoose.text(info["summary"]) ?? ""
                self.changes = (info["changes"] as? [Any] ?? []).compactMap { item in
                    guard let raw = item as? [String: Any], let label = FabulaLoose.text(raw["label"]) else { return nil }
                    return FabulaChange(label: label, up: FabulaLoose.text(raw["dir"]) != "down", strength: FabulaLoose.text(raw["strength"]) ?? "")
                }
                self.unseenCount = unseen.count
                self.phase = .done
            case .failure(let failure):
                self.error = failure.localizedDescription
            }
        }
    }

    func reset() {
        ticket += 1
        loading = false
        error = nil
        phase = .pick
        films = []
        ratings = [:]
        shown = []
        committed = []
    }

    func backToRecommend() {
        FabulaNav.shared.tab = .recommend
        FabulaDeck.shared.reload(source: "refiner")
        note("fabula refiner closed rated=\(ratings.count) unseen=\(unseenCount)")
        reset()
    }

    private func commit(_ batch: [FabulaFilm]) {
        var saved = 0
        for film in batch {
            guard let value = ratings[film.tmdb], !committed.contains(film.tmdb) else { continue }
            OrtusStore.shared.saveLog(film, rating: value, comment: "", source: "refiner")
            committed.insert(film.tmdb)
            saved += 1
        }
        note("fabula refiner batch committed saved=\(saved) batch=\(batch.count) sessionRated=\(ratings.count) shown=\(shown.count)")
    }

    private func fetch(source: String) {
        guard FabulaNet.connected else {
            error = "Cloud isn't connected."
            note("fabula refiner refine skipped reason=not connected source=\(source)")
            return
        }
        ticket += 1
        let mine = ticket
        loading = true
        error = nil
        let body: [String: Any] = ["langs": langs, "genres": genres, "exclude": Array(Set(shown)).sorted()]
        FabulaAINet.call("refine", body: body, detail: { "films=\(FabulaAINet.films($0).count) source=\(source)" }) { [weak self] result in
            guard let self, mine == self.ticket else { return }
            self.loading = false
            switch result {
            case .success(let json):
                let found = FabulaAINet.films(json)
                if found.isEmpty {
                    self.error = "No more films match. Try different filters."
                    if self.films.isEmpty { self.phase = .pick }
                    return
                }
                self.films = found
                self.shown.append(contentsOf: found.map(\.tmdb))
                for film in found { self.catalogue[film.tmdb] = film }
                self.phase = .list
            case .failure(let failure):
                self.error = failure.localizedDescription
            }
        }
    }
}

struct FabulaRefinerView: View {
    @ObservedObject var nav: FabulaNav
    @ObservedObject private var model = FabulaRefiner.shared

    var body: some View {
        Group {
            switch model.phase {
            case .pick: pick
            case .list: list
            case .done: done
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Fab.ground)
    }

    private func toggle(_ name: String, in list: [String]) -> [String] {
        list.contains(name) ? list.filter { $0 != name } : list + [name]
    }

    private var pick: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Refine your taste").font(Fab.serif(30)).foregroundStyle(Fab.ink)
                Text("Rate films you have seen. Leave the rest. Recommend learns from both.").font(Fab.sans(14)).foregroundStyle(Fab.muted)
                group("Language", options: FabulaRefiner.languages, chosen: model.langs) { model.langs = $0 }
                group("Genre", options: FabulaRefiner.genres, chosen: model.genres) { model.genres = $0 }
                if let error = model.error { Text(error).font(Fab.sans(12.5)).foregroundStyle(Fab.muted) }
                HStack(spacing: 12) {
                    FabulaButton(title: "Start refining", filled: true, height: 44) { model.start() }
                        .frame(width: 200)
                        .opacity(model.loading ? 0.45 : 1)
                        .disabled(model.loading)
                    if model.loading { ProgressView().controlSize(.small) }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    private func group(_ title: String, options: [String], chosen: [String], apply: @escaping ([String]) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Fab.sans(11, .bold)).tracking(1.4).foregroundStyle(Fab.faint)
            FabulaFlow {
                FabulaChip(title: "Any", on: chosen.isEmpty) { apply([]) }
                ForEach(options, id: \.self) { name in
                    FabulaChip(title: name, on: chosen.contains(name)) { apply(toggle(name, in: chosen)) }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Refiner").font(Fab.serif(26)).foregroundStyle(Fab.ink)
                    Text(model.scope).font(Fab.sans(13)).foregroundStyle(Fab.muted).lineLimit(1)
                    Spacer()
                    Text("\(model.ratedCount) rated")
                        .font(Fab.sans(12, .semibold))
                        .foregroundStyle(Fab.washText)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Fab.wash))
                }
                if model.loading && model.films.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 300)
                } else {
                    ForEach(model.films) { film in row(film) }
                    footer
                }
            }
            .frame(maxWidth: 820)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ film: FabulaFilm) -> some View {
        let value = model.ratings[film.tmdb]
        let binding = Binding<Double>(get: { value ?? 5 }, set: { model.rate(film, $0) })
        return HStack(alignment: .top, spacing: 16) {
            FabulaPoster(url: film.thumbURL, radius: 8).frame(width: 78, height: 117)
            VStack(alignment: .leading, spacing: 5) {
                Text(film.title).font(Fab.serif(18)).foregroundStyle(Fab.ink).lineLimit(1)
                Text([film.year.map { String($0) } ?? "", film.director].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Fab.sans(12.5)).foregroundStyle(Fab.muted).lineLimit(1)
                Text(film.overview).font(Fab.sans(12.5)).foregroundStyle(Fab.faint).lineLimit(2)
                Spacer(minLength: 2)
                HStack(spacing: 12) {
                    Slider(value: binding, in: 1...10, step: 1)
                        .tint(value == nil ? Fab.line : Fab.accent)
                        .saturation(value == nil ? 0 : 1)
                    Text(value.map { "\(Int($0)) / 10" } ?? "Not seen")
                        .font(Fab.sans(12.5, .semibold))
                        .foregroundStyle(value == nil ? Fab.faint : Fab.accent)
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fab.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Fab.line, lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.error { Text(error).font(Fab.sans(12.5)).foregroundStyle(Fab.muted) }
            HStack(spacing: 12) {
                FabulaButton(title: "Stop", color: Fab.muted, height: 44) { model.stop() }
                FabulaButton(title: "Continue: 10 more", filled: true, height: 44) { model.more() }
                if model.loading { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: 460)
            .opacity(model.loading ? 0.5 : 1)
            .disabled(model.loading)
        }
        .padding(.top, 6)
    }

    private var done: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Fab.yes)
                Text("Taste updated").font(Fab.serif(30)).foregroundStyle(Fab.ink)
                Text("\(model.ratedCount) films rated, \(model.unseenCount) not seen. Recommend uses this from your next card.")
                    .font(Fab.sans(14)).foregroundStyle(Fab.muted)
                if !model.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT CHANGED").font(Fab.sans(11, .bold)).tracking(1.4).foregroundStyle(Fab.faint)
                        ForEach(model.changes) { change in
                            HStack {
                                Text(change.label).font(Fab.sans(14, .semibold)).foregroundStyle(Fab.ink)
                                Spacer()
                                Text("\(change.up ? "↑" : "↓") \(change.strength)")
                                    .font(Fab.sans(13, .semibold))
                                    .foregroundStyle(change.up ? Fab.yes : Fab.no)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fab.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Fab.line, lineWidth: 1))
                        }
                    }
                }
                if !model.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR TASTE, IN A LINE").font(Fab.sans(11, .bold)).tracking(1.4).foregroundStyle(Fab.faint)
                        Text(model.summary).font(Fab.serif(17, .regular)).foregroundStyle(Fab.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 12) {
                    FabulaButton(title: "Back to Recommend", filled: true, height: 44) { model.backToRecommend() }
                    FabulaButton(title: "Refine something else", color: Fab.muted, height: 44) { model.reset() }
                }
                .frame(maxWidth: 460)
                .padding(.top, 8)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
}
