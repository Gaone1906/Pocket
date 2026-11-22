import AppKit
import Foundation

enum FabulaLoose {
    static func text(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, number.doubleValue.isFinite { return number.doubleValue }
        if let text = value as? String, let parsed = Double(text), parsed.isFinite { return parsed }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        guard let number = number(value), abs(number) < 1e15 else { return nil }
        return Int(number)
    }

    static func texts(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { text($0) }
    }
}

enum FabulaClock {
    private static let precise: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    static func now() -> String { precise.string(from: Date()) }

    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let trimmed = text.replacingOccurrences(of: #"\.(\d{3})\d*"#, with: ".$1", options: .regularExpression)
        return precise.date(from: trimmed) ?? plain.date(from: text)
    }

    static func newer(_ a: String?, than b: String?) -> Bool {
        switch (date(a), date(b)) {
        case let (left?, right?): return left > right
        case (.some(_), .none): return true
        case (.none, .some(_)): return false
        default: return (a ?? "") > (b ?? "")
        }
    }
}

enum FabulaFormat {
    static func runtime(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "" }
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func rating(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func count(_ value: Int?, _ one: String, _ many: String) -> String {
        guard let value, value > 0 else { return "" }
        return "\(value) \(value == 1 ? one : many)"
    }

    static func line(kind: FabulaKind, year: Int?, runtime: Int?, genres: [String], language: String, director: String, format: String,
                     episodes: Int?, seasons: Int?, byline: Bool) -> String {
        let when = year.map { String($0) } ?? ""
        let tail = byline ? director : genres.prefix(2).joined(separator: ", ")
        let parts: [String]
        switch kind {
        case .anime:
            parts = [when, format, format == "Movie" ? Self.runtime(runtime) : count(episodes, "ep", "eps"), tail.isEmpty ? director : tail]
        case .show:
            parts = [when, count(seasons, "season", "seasons"), (runtime ?? 0) > 0 ? "\(runtime ?? 0)m" : "", tail,
                     language == "English" ? "" : language]
        case .movie:
            parts = byline ? [when, Self.runtime(runtime), director] : [when, Self.runtime(runtime), tail, language == "English" ? "" : language]
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func added(_ text: String) -> String {
        guard let date = FabulaClock.date(text) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func poster(_ path: String, size: String = "w500") -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://image.tmdb.org/t/p/\(size)" + (path.hasPrefix("/") ? path : "/" + path))
    }
}

enum FabulaKind: String, CaseIterable, Identifiable {
    case movie, show, anime

    static let defaultsKey = "fabula.kind"
    private static let movieLanguages = ["English", "Hindi", "Telugu", "Tamil", "Malayalam", "Kannada", "Korean", "Japanese", "Spanish", "French"]
    private static let movieGenres = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Family", "Fantasy", "Horror", "Mystery",
                                      "Romance", "Sci-fi", "Thriller", "War"]

    var id: String { rawValue }

    var name: String {
        switch self {
        case .movie: return "Movies"
        case .show: return "Shows"
        case .anime: return "Anime"
        }
    }

    func noun(_ count: Int = 1) -> String {
        switch self {
        case .movie: return count == 1 ? "film" : "films"
        case .show: return count == 1 ? "show" : "shows"
        case .anime: return "anime"
        }
    }

    var languages: [String] {
        switch self {
        case .movie: return Self.movieLanguages
        case .show: return ["English", "Korean", "Hindi"]
        case .anime: return []
        }
    }

    var genres: [String] {
        switch self {
        case .movie: return Self.movieGenres
        case .show: return ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Family", "Fantasy", "Mystery", "Romance", "Sci-fi", "War"]
        case .anime: return ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-fi", "Slice of Life", "Sports",
                             "Supernatural", "Thriller"]
        }
    }

    var refinerLanguages: [String] {
        self == .movie ? ["English", "Hindi", "Telugu", "Tamil", "Malayalam", "Kannada", "Korean", "Japanese", "Spanish"] : languages
    }

    var refinerGenres: [String] {
        self == .movie ? ["Action", "Animation", "Comedy", "Crime", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-fi", "Thriller", "War"] : genres
    }

    var searchMinimum: Int { self == .anime ? 3 : 2 }

    func filterKey(_ name: String) -> String {
        self == .movie ? "fabula.\(name)" : "fabula.\(name).\(rawValue)"
    }

    func saved(_ name: String, allowed: [String]) -> [String] {
        (UserDefaults.standard.stringArray(forKey: filterKey(name)) ?? []).filter { allowed.contains($0) }
    }

    static var current: FabulaKind {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(FabulaKind.init(rawValue:)) ?? .movie
    }

    static func of(_ kind: String?, id: Int) -> FabulaKind {
        if let kind, let known = FabulaKind(rawValue: kind) { return known }
        if id >= 200_000_000 { return .anime }
        return id >= 100_000_000 ? .show : .movie
    }

    static func named(_ name: String) -> FabulaKind? {
        allCases.first { $0.name == name }
    }
}

enum FabulaVerdict: String {
    case yes
    case no
    case superlike = "super"
    case seen
}

struct FabulaFilm: Identifiable, Equatable {
    let tmdb: Int
    let kind: FabulaKind
    let title: String
    let year: Int?
    let runtime: Int?
    let language: String
    let genres: [String]
    let director: String
    let cast: [String]
    let overview: String
    let poster: String
    let backdrop: String
    let vote: Double?
    let imdb: Double?
    let mal: Double?
    let seasons: Int?
    let episodes: Int?
    let format: String
    let providers: [String]
    let why: String

    var id: Int { tmdb }

    init?(_ raw: [String: Any]) {
        guard let tmdb = FabulaLoose.int(raw["tmdb"]), tmdb > 0, let title = FabulaLoose.text(raw["title"]) else { return nil }
        self.tmdb = tmdb
        self.title = title
        kind = FabulaKind.of(FabulaLoose.text(raw["kind"]), id: tmdb)
        year = FabulaLoose.int(raw["year"])
        runtime = FabulaLoose.int(raw["runtime"])
        language = FabulaLoose.text(raw["language"]) ?? ""
        genres = FabulaLoose.texts(raw["genres"])
        director = FabulaLoose.text(raw["director"]) ?? ""
        cast = FabulaLoose.texts(raw["cast"])
        overview = FabulaLoose.text(raw["overview"]) ?? ""
        poster = FabulaLoose.text(raw["poster"]) ?? ""
        backdrop = FabulaLoose.text(raw["backdrop"]) ?? ""
        vote = FabulaLoose.number(raw["vote"])
        imdb = FabulaLoose.number(raw["imdb"])
        mal = FabulaLoose.number(raw["mal"]) ?? FabulaLoose.number(raw["mal_score"])
        seasons = FabulaLoose.int(raw["seasons"])
        episodes = FabulaLoose.int(raw["episodes"])
        format = FabulaLoose.text(raw["format"]) ?? ""
        providers = FabulaLoose.texts(raw["providers"])
        why = FabulaLoose.text(raw["why"]) ?? ""
    }

    var posterURL: URL? { FabulaFormat.poster(poster) }
    var thumbURL: URL? { FabulaFormat.poster(poster, size: "w185") }

    var meta: String {
        FabulaFormat.line(kind: kind, year: year, runtime: runtime, genres: genres, language: language, director: director, format: format,
                          episodes: episodes, seasons: seasons, byline: false)
    }

    var credits: String {
        FabulaFormat.line(kind: kind, year: year, runtime: runtime, genres: genres, language: language, director: director, format: format,
                          episodes: episodes, seasons: seasons, byline: true)
    }

    var people: String {
        let names = cast.prefix(3).joined(separator: ", ")
        return [names, providers.first ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var streaming: String? {
        guard !providers.isEmpty else { return nil }
        let names = providers.prefix(2).joined(separator: " and ")
        return "Streaming on \(names) in India"
    }

    var record: [String: Any] {
        var out: [String: Any] = ["tmdb": tmdb, "kind": kind.rawValue, "title": title, "language": language, "genres": genres]
        if let seasons { out["seasons"] = seasons }
        if let episodes { out["episodes"] = episodes }
        if !format.isEmpty { out["format"] = format }
        out["year"] = Self.orNull(year)
        out["runtime"] = Self.orNull(runtime)
        out["poster"] = Self.orNull(poster)
        out["director"] = Self.orNull(director)
        return out
    }

    static func orNull(_ value: Int?) -> Any {
        if let value { return value }
        return NSNull()
    }

    static func orNull(_ value: String) -> Any {
        if value.isEmpty { return NSNull() }
        return value
    }
}

struct FabulaHit: Identifiable {
    let tmdb: Int
    let title: String
    let original: String
    let year: Int?
    let language: String
    let format: String
    let poster: String

    var id: Int { tmdb }

    init?(_ raw: [String: Any]) {
        guard let tmdb = FabulaLoose.int(raw["tmdb"]), tmdb > 0, let title = FabulaLoose.text(raw["title"]) else { return nil }
        self.tmdb = tmdb
        self.title = title
        original = FabulaLoose.text(raw["original_title"]) ?? ""
        year = FabulaLoose.int(raw["year"])
        language = FabulaLoose.text(raw["language"]) ?? ""
        format = FabulaLoose.text(raw["format"]) ?? ""
        poster = FabulaLoose.text(raw["poster"]) ?? ""
    }

    var thumbURL: URL? { FabulaFormat.poster(poster, size: "w185") }

    var meta: String {
        [year.map { String($0) } ?? "", format.isEmpty ? language : format, original == title ? "" : original].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct FabulaEntry: Identifiable {
    private(set) var raw: [String: Any]

    init?(_ raw: [String: Any]) {
        let number = FabulaLoose.int(raw["tmdb"]).map({ String($0) })
        guard let id = FabulaLoose.text(raw["id"]) ?? number else { return nil }
        self.raw = raw
        self.raw["id"] = id
    }

    var id: String { FabulaLoose.text(raw["id"]) ?? "" }
    var tmdb: Int { FabulaLoose.int(raw["tmdb"]) ?? Int(id) ?? 0 }
    var title: String { FabulaLoose.text(raw["title"]) ?? "" }
    var year: Int? { FabulaLoose.int(raw["year"]) }
    var poster: String { FabulaLoose.text(raw["poster"]) ?? "" }
    var language: String { FabulaLoose.text(raw["language"]) ?? "" }
    var genres: [String] { FabulaLoose.texts(raw["genres"]) }
    var director: String { FabulaLoose.text(raw["director"]) ?? "" }
    var runtime: Int? { FabulaLoose.int(raw["runtime"]) }
    var kind: FabulaKind { FabulaKind.of(FabulaLoose.text(raw["kind"]), id: tmdb) }
    var seasons: Int? { FabulaLoose.int(raw["seasons"]) }
    var episodes: Int? { FabulaLoose.int(raw["episodes"]) }
    var format: String { FabulaLoose.text(raw["format"]) ?? "" }
    var verdict: FabulaVerdict? { FabulaLoose.text(raw["verdict"]).flatMap(FabulaVerdict.init(rawValue:)) }
    var rating: Double? { FabulaLoose.number(raw["rating"]) }
    var comment: String { (raw["comment"] as? String) ?? "" }
    var at: String { FabulaLoose.text(raw["at"]) ?? "" }
    var logged: String { FabulaLoose.text(raw["logged"]) ?? "" }
    var updated: String { FabulaLoose.text(raw["updated"]) ?? "" }

    var thumbURL: URL? { FabulaFormat.poster(poster, size: "w185") }

    var heading: String {
        guard let year else { return title }
        return "\(title) · \(year)"
    }

    var film: FabulaFilm? {
        var copy = raw
        if copy["tmdb"] == nil { copy["tmdb"] = tmdb }
        return FabulaFilm(copy)
    }

    var meta: String {
        if kind != .movie {
            return FabulaFormat.line(kind: kind, year: year, runtime: runtime, genres: genres, language: language, director: director, format: format,
                                     episodes: episodes, seasons: seasons, byline: false)
        }
        return [year.map { String($0) } ?? "", FabulaFormat.runtime(runtime), genres.first ?? "", language == "English" ? "" : language]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func stamped(_ changes: [String: Any]) -> FabulaEntry {
        var copy = self
        for (key, value) in changes { copy.raw[key] = value }
        return copy
    }
}

struct FabulaBook {
    var logs: [FabulaEntry] = []
    var swipes: [FabulaEntry] = []
    var unseen: [FabulaEntry] = []

    static let legacyKeys = ["quotes", "stories", "reels", "videos"]

    static func decode(_ data: Data) throws -> FabulaBook {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "fabula", code: 1, userInfo: [NSLocalizedDescriptionKey: "not an object"])
        }
        func list(_ key: String) -> [FabulaEntry] {
            var out: [FabulaEntry] = []
            var index: [String: Int] = [:]
            for item in object[key] as? [Any] ?? [] {
                guard let raw = item as? [String: Any], let entry = FabulaEntry(raw) else { continue }
                if let at = index[entry.id] {
                    if FabulaClock.newer(entry.updated, than: out[at].updated) { out[at] = entry }
                } else {
                    index[entry.id] = out.count
                    out.append(entry)
                }
            }
            return out
        }
        return FabulaBook(logs: list("logs"), swipes: list("swipes"), unseen: list("unseen"))
    }

    static func isLegacy(_ data: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return legacyKeys.contains { object[$0] != nil } || object["logs"] == nil || object["swipes"] == nil
    }

    func encode() throws -> Data {
        let object: [String: Any] = ["logs": logs.map(\.raw), "swipes": swipes.map(\.raw), "unseen": unseen.map(\.raw)]
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NSError(domain: "fabula", code: 2, userInfo: [NSLocalizedDescriptionKey: "not valid JSON"])
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

final class OrtusStore: ObservableObject {
    static let shared = OrtusStore()
    static let name = "ortus"

    @Published private(set) var logs: [FabulaEntry] = []
    @Published private(set) var swipes: [FabulaEntry] = []
    @Published private(set) var unseen: [FabulaEntry] = []

    var onChange: (() -> Void)?
    private let file = PocketData.ortus

    private init() {
        let vault = DataVault.shared
        vault.register(Self.name) { [weak self] data in self?.merge(data) }
        CloudSync.shared.register(Self.name) { [weak self] data in self?.adopt(data) }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                let book = try FabulaBook.decode(data)
                logs = book.logs
                swipes = book.swipes
                unseen = book.unseen
                note("fabula book loaded logs=\(logs.count) swipes=\(swipes.count) unseen=\(unseen.count) path=\(file.path)")
                if FabulaBook.isLegacy(data) {
                    vault.keepAside(data, name: Self.name, reason: "before-fabula")
                    save()
                    note("fabula book replaced old library shape path=\(file.path)")
                }
                return
            } catch {
                note("fabula book load failed path=\(file.path) error=\(error.localizedDescription)")
                vault.quarantine(file, name: Self.name)
            }
        }
        if let (saved, snap) = vault.recover(Self.name, decode: FabulaBook.decode) {
            logs = saved.logs
            swipes = saved.swipes
            unseen = saved.unseen
            note("fabula book recovered from=\(snap.url.path) logs=\(logs.count) swipes=\(swipes.count) unseen=\(unseen.count)")
            save()
            return
        }
        note("fabula book empty path=\(file.path)")
    }

    func watchlist(_ kind: FabulaKind) -> [FabulaEntry] {
        let logged = Set(logs.map(\.id))
        return swipes
            .filter { ($0.verdict == .yes || $0.verdict == .superlike) && !logged.contains($0.id) && $0.kind == kind }
            .sorted { a, b in
                if (a.verdict == .superlike) != (b.verdict == .superlike) { return a.verdict == .superlike }
                return FabulaClock.newer(a.at, than: b.at)
            }
    }

    var known: [Int] { Array(Set(logs.map(\.tmdb) + swipes.map(\.tmdb))).filter { $0 > 0 } }

    func log(_ id: String) -> FabulaEntry? { logs.first { $0.id == id } }
    func swipe(_ id: String) -> FabulaEntry? { swipes.first { $0.id == id } }

    @discardableResult
    func record(_ film: FabulaFilm, _ verdict: FabulaVerdict, source: String) -> FabulaEntry? {
        let now = FabulaClock.now()
        var raw = film.record
        raw["id"] = String(film.tmdb)
        raw["verdict"] = verdict.rawValue
        raw["at"] = now
        raw["updated"] = now
        guard let entry = FabulaEntry(raw) else { return nil }
        let previous = swipe(entry.id)
        put(entry, in: &swipes)
        note("fabula swipe saved tmdb=\(film.tmdb) verdict=\(verdict.rawValue) source=\(source) replaced=\(previous?.verdict?.rawValue ?? "none") swipes=\(swipes.count)")
        save()
        return previous
    }

    func restore(_ previous: FabulaEntry, source: String) {
        let entry = previous.stamped(["updated": FabulaClock.now()])
        put(entry, in: &swipes)
        note("fabula swipe restored tmdb=\(entry.tmdb) verdict=\(entry.verdict?.rawValue ?? "none") source=\(source)")
        save()
    }

    func unswipe(_ id: String, source: String) {
        guard let index = swipes.firstIndex(where: { $0.id == id }) else { return }
        let gone = swipes.remove(at: index)
        note("fabula swipe removed tmdb=\(gone.tmdb) verdict=\(gone.verdict?.rawValue ?? "none") source=\(source) swipes=\(swipes.count)")
        save()
    }

    func saveLog(_ film: FabulaFilm, rating: Double, comment: String, source: String, origin: String? = nil) {
        let now = FabulaClock.now()
        let id = String(film.tmdb)
        let existing = log(id)
        var raw = existing?.raw ?? [:]
        for (key, value) in film.record { raw[key] = value }
        raw["id"] = id
        raw["rating"] = min(10, max(1, rating))
        raw["comment"] = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        raw["logged"] = existing.map { $0.logged.isEmpty ? now : $0.logged } ?? now
        raw["updated"] = now
        if let origin { raw["source"] = origin }
        guard let entry = FabulaEntry(raw) else { return }
        put(entry, in: &logs)
        note("fabula log saved tmdb=\(film.tmdb) rating=\(FabulaFormat.rating(entry.rating)) commentLength=\(entry.comment.count) new=\(existing == nil) source=\(source) origin=\(origin ?? "none") logs=\(logs.count)")
        save()
    }

    func markUnseen(_ films: [FabulaFilm], source: String) {
        guard !films.isEmpty else { return }
        let now = FabulaClock.now()
        var added = 0
        for film in films {
            var raw: [String: Any] = ["id": String(film.tmdb), "tmdb": film.tmdb, "kind": film.kind.rawValue, "title": film.title, "at": now, "updated": now]
            raw["year"] = FabulaFilm.orNull(film.year)
            guard let entry = FabulaEntry(raw) else { continue }
            if !unseen.contains(where: { $0.id == entry.id }) { added += 1 }
            put(entry, in: &unseen)
        }
        note("fabula unseen saved films=\(films.count) new=\(added) source=\(source) unseen=\(unseen.count)")
        save()
    }

    func deleteLog(_ id: String, source: String) {
        guard let index = logs.firstIndex(where: { $0.id == id }) else { return }
        let gone = logs.remove(at: index)
        note("fabula log removed tmdb=\(gone.tmdb) source=\(source) logs=\(logs.count)")
        save()
    }

    private func put(_ entry: FabulaEntry, in list: inout [FabulaEntry]) {
        if let index = list.firstIndex(where: { $0.id == entry.id }) {
            list[index] = entry
        } else {
            list.append(entry)
        }
    }

    func merge(_ data: Data) {
        do {
            let incoming = try FabulaBook.decode(data)
            if let current = try? FabulaBook(logs: logs, swipes: swipes, unseen: unseen).encode() {
                DataVault.shared.keepAside(current, name: Self.name, reason: "before-merge")
            }
            var added = 0, replaced = 0
            func fold(_ items: [FabulaEntry], into list: inout [FabulaEntry]) {
                for item in items {
                    if let index = list.firstIndex(where: { $0.id == item.id }) {
                        if FabulaClock.newer(item.updated, than: list[index].updated) {
                            list[index] = item
                            replaced += 1
                        }
                    } else {
                        list.append(item)
                        added += 1
                    }
                }
            }
            fold(incoming.logs, into: &logs)
            fold(incoming.swipes, into: &swipes)
            fold(incoming.unseen, into: &unseen)
            save()
            note("fabula book merged added=\(added) replaced=\(replaced) logs=\(logs.count) swipes=\(swipes.count) unseen=\(unseen.count)")
        } catch {
            note("fabula book merge failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    func adopt(_ data: Data) {
        do {
            let incoming = try FabulaBook.decode(data)
            let before = (logs.count, swipes.count, unseen.count)
            logs = incoming.logs
            swipes = incoming.swipes
            unseen = incoming.unseen
            save()
            note("fabula book adopted cloud logsBefore=\(before.0) swipesBefore=\(before.1) unseenBefore=\(before.2) logs=\(logs.count) swipes=\(swipes.count) unseen=\(unseen.count)")
        } catch {
            note("fabula book adopt failed bytes=\(data.count) error=\(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try FabulaBook(logs: logs, swipes: swipes, unseen: unseen).encode()
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            DataVault.shared.snapshot(data, name: Self.name, count: logs.count + swipes.count + unseen.count)
        } catch {
            note("fabula book save failed logs=\(logs.count) swipes=\(swipes.count) unseen=\(unseen.count) error=\(error.localizedDescription)")
        }
        onChange?()
    }
}

struct FabulaFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum FabulaNet {
    static var connected: Bool { CloudSync.shared.baseURL != nil && CloudSync.shared.key != nil }

    static func rpc(_ name: String, body: [String: Any], done: @escaping (Result<Any, Error>) -> Void) {
        post("/rest/v1/rpc/" + name, body: body, done: done)
    }

    static func function(_ name: String, body: [String: Any], timeout: TimeInterval = 25, done: @escaping (Result<Any, Error>) -> Void) {
        post("/functions/v1/" + name, body: body, timeout: timeout, done: done)
    }

    private static func post(_ path: String, body: [String: Any], timeout: TimeInterval = 25, done: @escaping (Result<Any, Error>) -> Void) {
        guard let base = CloudSync.shared.baseURL, let key = CloudSync.shared.key, let url = URL(string: base + path) else {
            DispatchQueue.main.async { done(.failure(FabulaFailure(message: "cloud not connected"))) }
            return
        }
        guard JSONSerialization.isValidJSONObject(body), let payload = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { done(.failure(FabulaFailure(message: "request body not valid"))) }
            return
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.hasPrefix("sb_") { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.httpBody = payload
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Any, Error>
            if let error {
                result = .failure(error)
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { $0.isEmpty ? nil : try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
                if (200..<300).contains(status), let json {
                    result = .success(json)
                } else {
                    let info = json as? [String: Any]
                    let message = (info?["error"] ?? info?["message"] ?? info?["msg"]) as? String
                    result = .failure(FabulaFailure(message: message ?? "HTTP \(status)"))
                }
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }
}

struct FabulaMove {
    let film: FabulaFilm
    let verdict: FabulaVerdict
    let previous: FabulaEntry?
    var logged = false
}

final class FabulaDeck: ObservableObject {
    static let shared = FabulaDeck()

    @Published private(set) var cards: [FabulaFilm] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var history: [FabulaMove] = []
    @Published private(set) var tonight: [FabulaFilm] = []
    @Published private(set) var kind: FabulaKind = FabulaKind.current
    @Published private(set) var langs: [String] = FabulaKind.current.saved("langs", allowed: FabulaKind.current.languages)
    @Published private(set) var genres: [String] = FabulaKind.current.saved("genres", allowed: FabulaKind.current.genres)

    private var ticket = 0
    private var stale = false

    private init() {}

    var top: FabulaFilm? { cards.first }
    var canUndo: Bool { !history.isEmpty }

    func setKind(_ value: FabulaKind) {
        guard value != kind else { return }
        kind = value
        UserDefaults.standard.set(value.rawValue, forKey: FabulaKind.defaultsKey)
        langs = value.saved("langs", allowed: value.languages)
        genres = value.saved("genres", allowed: value.genres)
        history = []
        note("fabula kind changed kind=\(value.rawValue) langs=\(langs.count) genres=\(genres.count)")
        reload(source: "kind")
    }

    func setLangs(_ value: [String]) {
        guard value != langs else { return }
        langs = value
        UserDefaults.standard.set(value, forKey: kind.filterKey("langs"))
        note("fabula filter changed kind=\(kind.rawValue) langs=\(value.joined(separator: ","))")
        reload(source: "filter")
    }

    func setGenres(_ value: [String]) {
        guard value != genres else { return }
        genres = value
        UserDefaults.standard.set(value, forKey: kind.filterKey("genres"))
        note("fabula filter changed kind=\(kind.rawValue) genres=\(value.joined(separator: ","))")
        reload(source: "filter")
    }

    func reload(source: String) {
        stale = false
        cards = []
        loading = false
        fetch(source: source)
    }

    func markStale(source: String) {
        stale = true
        note("fabula deck marked stale source=\(source) cards=\(cards.count)")
    }

    func refill(source: String) {
        if stale {
            stale = false
            reload(source: source + " stale")
            return
        }
        guard cards.count <= 5, !loading else { return }
        fetch(source: source)
    }

    private func fetch(source: String) {
        ticket += 1
        let mine = ticket
        guard FabulaNet.connected else {
            loading = false
            failed = true
            note("fabula deck skipped reason=not connected kind=\(kind.rawValue) source=\(source)")
            return
        }
        loading = true
        failed = false
        let exclude = Array(Set(cards.map(\.tmdb) + OrtusStore.shared.known + history.map(\.film.tmdb))).sorted()
        let asked = kind
        let body: [String: Any] = ["p_kind": asked.rawValue,
                                   "p_langs": langs.isEmpty || asked == .anime ? NSNull() as Any : langs as Any,
                                   "p_genres": genres.isEmpty ? NSNull() as Any : genres as Any,
                                   "p_limit": 20, "p_exclude": exclude]
        FabulaNet.rpc("fabula_deck", body: body) { [weak self] result in
            guard let self, mine == self.ticket else { return }
            self.loading = false
            switch result {
            case .success(let json):
                let films = (json as? [Any] ?? []).compactMap { ($0 as? [String: Any]).flatMap(FabulaFilm.init) }
                let skip = Set(self.cards.map(\.tmdb) + OrtusStore.shared.known)
                var seen = Set<Int>()
                let fresh = films.filter { !skip.contains($0.tmdb) && seen.insert($0.tmdb).inserted }
                self.cards.append(contentsOf: fresh)
                self.failed = self.cards.isEmpty
                note("fabula deck fetched kind=\(asked.rawValue) source=\(source) received=\(films.count) added=\(fresh.count) cards=\(self.cards.count) langs=\(self.langs.count) genres=\(self.genres.count) excluded=\(exclude.count)")
            case .failure(let error):
                self.failed = self.cards.isEmpty
                note("fabula deck fetch failed kind=\(asked.rawValue) source=\(source) error=\(error.localizedDescription) cards=\(self.cards.count)")
            }
        }
    }

    func act(_ verdict: FabulaVerdict, source: String) {
        guard let film = cards.first else { return }
        cards.removeFirst()
        let previous = OrtusStore.shared.record(film, verdict, source: source)
        history.append(FabulaMove(film: film, verdict: verdict, previous: previous))
        if history.count > 50 { history.removeFirst(history.count - 50) }
        if verdict == .yes || verdict == .superlike {
            tonight.removeAll { $0.tmdb == film.tmdb }
            tonight.insert(film, at: 0)
        }
        let nav = FabulaNav.shared
        switch verdict {
        case .superlike: nav.pick = film
        case .seen: nav.rate(film, mode: .swiped)
        default: break
        }
        refill(source: "swipe")
    }

    func superlike(_ film: FabulaFilm, source: String) {
        OrtusStore.shared.record(film, .superlike, source: source)
        cards.removeAll { $0.tmdb == film.tmdb }
        tonight.removeAll { $0.tmdb == film.tmdb }
        tonight.insert(film, at: 0)
        FabulaNav.shared.pick = film
    }

    func undo(source: String) {
        guard let move = history.popLast() else { return }
        let id = String(move.film.tmdb)
        if let previous = move.previous {
            OrtusStore.shared.restore(previous, source: source)
        } else {
            OrtusStore.shared.unswipe(id, source: source)
        }
        if move.logged { OrtusStore.shared.deleteLog(id, source: source) }
        tonight.removeAll { $0.tmdb == move.film.tmdb }
        cards.removeAll { $0.tmdb == move.film.tmdb }
        cards.insert(move.film, at: 0)
        let nav = FabulaNav.shared
        if nav.pick?.tmdb == move.film.tmdb { nav.pick = nil }
        if nav.rating?.film.tmdb == move.film.tmdb { nav.rating = nil }
        note("fabula undo tmdb=\(move.film.tmdb) verdict=\(move.verdict.rawValue) logged=\(move.logged) source=\(source)")
    }

    func markLogged(_ tmdb: Int) {
        guard let index = history.lastIndex(where: { $0.film.tmdb == tmdb }) else { return }
        history[index].logged = true
    }
}

enum FabulaTab: String, CaseIterable, Identifiable {
    case recommend, watchlist, log, refiner, ai

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ai: return "AI Mode"
        default: return rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .recommend: return "rectangle.portrait"
        case .watchlist: return "bookmark"
        case .log: return "list.bullet"
        case .refiner: return "slider.horizontal.3"
        case .ai: return "sparkles"
        }
    }
}

struct FabulaRating: Identifiable {
    enum Mode { case swiped, seen, edit }

    let film: FabulaFilm
    let mode: Mode
    let rating: Double?
    let comment: String

    var id: Int { film.tmdb }
}

final class FabulaNav: ObservableObject {
    static let shared = FabulaNav()

    @Published var tab: FabulaTab = FabulaTab(rawValue: UserDefaults.standard.string(forKey: "fabula.tab") ?? "") ?? .recommend {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "fabula.tab") }
    }
    @Published var pick: FabulaFilm?
    @Published var rating: FabulaRating?

    private init() {}

    func rate(_ film: FabulaFilm, mode: FabulaRating.Mode) {
        let existing = OrtusStore.shared.log(String(film.tmdb))
        rating = FabulaRating(film: film, mode: mode, rating: existing?.rating, comment: existing?.comment ?? "")
    }

    func finish(_ sheet: FabulaRating, rating: Double?, comment: String, save: Bool, source: String) {
        let store = OrtusStore.shared
        let id = String(sheet.film.tmdb)
        switch sheet.mode {
        case .swiped:
            if save, let rating {
                store.saveLog(sheet.film, rating: rating, comment: comment, source: source)
                FabulaDeck.shared.markLogged(sheet.film.tmdb)
            }
        case .seen:
            store.record(sheet.film, .seen, source: source)
            if save, let rating { store.saveLog(sheet.film, rating: rating, comment: comment, source: source) }
        case .edit:
            if save, let rating {
                store.saveLog(sheet.film, rating: rating, comment: comment, source: source)
            } else if !save {
                store.deleteLog(id, source: source)
            }
        }
        note("fabula rating closed tmdb=\(sheet.film.tmdb) saved=\(save) rating=\(FabulaFormat.rating(rating)) source=\(source)")
        self.rating = nil
    }

    func watch(_ film: FabulaFilm, source: String) {
        let link: String
        switch film.kind {
        case .anime: link = "https://myanimelist.net/anime/\(film.tmdb - 200_000_000)"
        case .show: link = "https://www.themoviedb.org/tv/\(film.tmdb - 100_000_000)/watch?locale=IN"
        case .movie: link = "https://www.themoviedb.org/movie/\(film.tmdb)/watch?locale=IN"
        }
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        note("fabula watch tonight tmdb=\(film.tmdb) providers=\(film.providers.count) source=\(source)")
        pick = nil
    }
}

final class FabulaSearch: ObservableObject {
    @Published var query = "" {
        didSet { schedule() }
    }
    @Published private(set) var hits: [FabulaHit] = []
    @Published private(set) var busy = false
    @Published private(set) var adding: Int?

    private var work: DispatchWorkItem?
    private var ticket = 0

    func reset() {
        work?.cancel()
        ticket += 1
        query = ""
        hits = []
        busy = false
        adding = nil
    }

    private func schedule() {
        work?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= FabulaDeck.shared.kind.searchMinimum else {
            ticket += 1
            hits = []
            busy = false
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.run(text) }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func run(_ text: String) {
        ticket += 1
        let mine = ticket
        busy = true
        let kind = FabulaDeck.shared.kind
        let name = kind == .anime ? "fabula-anime" : "fabula-tmdb"
        var body: [String: Any] = ["action": "search", "q": String(text.prefix(kind == .anime ? 64 : 100))]
        if kind != .anime { body["kind"] = kind.rawValue }
        FabulaNet.function(name, body: body) { [weak self] result in
            guard let self, mine == self.ticket else { return }
            self.busy = false
            switch result {
            case .success(let json):
                let list = ((json as? [String: Any])?["results"] as? [Any]) ?? []
                self.hits = list.compactMap { ($0 as? [String: Any]).flatMap(FabulaHit.init) }
                note("fabula search done kind=\(kind.rawValue) length=\(text.count) results=\(self.hits.count)")
            case .failure(let error):
                self.hits = []
                note("fabula search failed kind=\(kind.rawValue) length=\(text.count) error=\(error.localizedDescription)")
            }
        }
    }

    func add(_ hit: FabulaHit, done: @escaping (FabulaFilm) -> Void) {
        guard adding == nil else { return }
        adding = hit.tmdb
        let kind = FabulaKind.of(nil, id: hit.tmdb)
        FabulaNet.function(kind == .anime ? "fabula-anime" : "fabula-tmdb", body: ["action": "add", "tmdb": hit.tmdb]) { [weak self] result in
            guard let self else { return }
            self.adding = nil
            switch result {
            case .success(let json):
                if let raw = (json as? [String: Any])?["movie"] as? [String: Any], let film = FabulaFilm(raw) {
                    note("fabula add done kind=\(kind.rawValue) tmdb=\(film.tmdb)")
                    done(film)
                } else {
                    note("fabula add failed kind=\(kind.rawValue) tmdb=\(hit.tmdb) error=no movie in answer")
                }
            case .failure(let error):
                note("fabula add failed kind=\(kind.rawValue) tmdb=\(hit.tmdb) error=\(error.localizedDescription)")
            }
        }
    }
}

struct FabulaTaste {
    let summary: String
    let more: [String]
    let less: [String]

    init?(_ raw: [String: Any]) {
        summary = FabulaLoose.text(raw["summary"]) ?? ""
        more = Self.labels(raw["more"])
        less = Self.labels(raw["less"])
        if summary.isEmpty && more.isEmpty && less.isEmpty { return nil }
    }

    private static func labels(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { item -> String? in
            if let text = FabulaLoose.text(item) { return text }
            guard let object = item as? [String: Any] else { return nil }
            return FabulaLoose.text(object["label"]) ?? FabulaLoose.text(object["name"]) ?? FabulaLoose.text(object["text"])
        }
    }
}

final class FabulaRefiner: ObservableObject {
    enum Stage { case pick, list, done }

    static let shared = FabulaRefiner()

    @Published private(set) var stage: Stage = .pick
    @Published private(set) var kind: FabulaKind = FabulaKind.current
    @Published private(set) var langs: [String] = []
    @Published private(set) var genres: [String] = []
    @Published private(set) var films: [FabulaFilm] = []
    @Published private(set) var scores: [Int: Int] = [:]
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    @Published private(set) var rated = 0
    @Published private(set) var skipped = 0
    @Published private(set) var taste: FabulaTaste?
    @Published private(set) var tasting = false
    @Published private(set) var tasteProblem: String?

    private var shown: [Int] = []
    private var fresh: [Int] = []
    private var ticket = 0
    private var tasteTicket = 0

    private init() {}

    var total: Int { rated + scores.count }

    var choice: String {
        let lang = langs.isEmpty ? "Any language" : langs.joined(separator: ", ")
        let genre = genres.isEmpty ? "Any genre" : genres.joined(separator: ", ")
        return [kind.name, kind == .anime ? "" : lang, genre].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func setKind(_ value: FabulaKind) {
        guard value != kind else { return }
        kind = value
        langs = []
        genres = []
    }

    func toggleLang(_ name: String?) {
        langs = Self.toggled(langs, name)
    }

    func toggleGenre(_ name: String?) {
        genres = Self.toggled(genres, name)
    }

    private static func toggled(_ list: [String], _ name: String?) -> [String] {
        guard let name else { return [] }
        return list.contains(name) ? list.filter { $0 != name } : list + [name]
    }

    func score(_ tmdb: Int, _ value: Int) {
        scores[tmdb] = min(10, max(1, value))
    }

    func begin() {
        ticket += 1
        tasteTicket += 1
        shown = []
        fresh = []
        rated = 0
        skipped = 0
        taste = nil
        tasting = false
        tasteProblem = nil
        films = []
        scores = [:]
        stage = .list
        note("fabula refiner started kind=\(kind.rawValue) langs=\(langs.joined(separator: ",")) genres=\(genres.joined(separator: ","))")
        fetch(source: "start")
    }

    func next() {
        guard !loading else { return }
        let counts = saveBatch()
        ticket += 1
        let mine = ticket
        loading = true
        problem = nil
        note("fabula refiner continue rated=\(counts.0) unseen=\(counts.1) total=\(rated)")
        CloudSync.shared.syncNow { [weak self] ok in
            guard let self, mine == self.ticket else { return }
            note("fabula refiner pushed ok=\(ok) source=continue")
            self.fetch(source: "continue")
        }
    }

    func retry() {
        guard !loading else { return }
        fetch(source: "retry")
    }

    func stop() {
        let counts = saveBatch()
        ticket += 1
        loading = false
        stage = .done
        FabulaDeck.shared.markStale(source: "refiner")
        note("fabula refiner stopped rated=\(counts.0) unseen=\(counts.1) totalRated=\(rated) totalUnseen=\(skipped)")
        guard !fresh.isEmpty else { return }
        tasteTicket += 1
        let mine = tasteTicket
        tasting = true
        tasteProblem = nil
        let ids = fresh
        CloudSync.shared.syncNow { [weak self] ok in
            guard let self, mine == self.tasteTicket else { return }
            note("fabula refiner pushed ok=\(ok) source=stop")
            FabulaNet.function("fabula-ai", body: ["action": "taste", "fresh": ids], timeout: 90) { [weak self] result in
                guard let self, mine == self.tasteTicket else { return }
                self.tasting = false
                switch result {
                case .success(let json):
                    let raw = (json as? [String: Any])?["taste"] as? [String: Any]
                    if let taste = raw.flatMap(FabulaTaste.init) {
                        self.taste = taste
                        if FabulaNav.shared.tab != .recommend { FabulaDeck.shared.markStale(source: "taste") }
                        note("fabula taste updated fresh=\(ids.count) more=\(taste.more.count) less=\(taste.less.count) summaryLength=\(taste.summary.count)")
                    } else {
                        self.tasteProblem = "No taste in the answer"
                        note("fabula taste failed fresh=\(ids.count) error=no taste in answer")
                    }
                case .failure(let error):
                    self.tasteProblem = error.localizedDescription
                    note("fabula taste failed fresh=\(ids.count) error=\(error.localizedDescription)")
                }
            }
        }
    }

    func again() {
        ticket += 1
        loading = false
        films = []
        scores = [:]
        stage = .pick
        note("fabula refiner reset source=again")
    }

    private func saveBatch() -> (Int, Int) {
        let store = OrtusStore.shared
        var count = 0
        var missed: [FabulaFilm] = []
        for film in films {
            if let value = scores[film.tmdb] {
                store.saveLog(film, rating: Double(value), comment: "", source: "refiner", origin: "refiner")
                fresh.append(film.tmdb)
                count += 1
            } else {
                missed.append(film)
            }
        }
        store.markUnseen(missed, source: "refiner")
        rated += count
        skipped += missed.count
        films = []
        scores = [:]
        return (count, missed.count)
    }

    private func fetch(source: String) {
        ticket += 1
        let mine = ticket
        guard FabulaNet.connected else {
            loading = false
            problem = "Cloud not connected"
            note("fabula refiner fetch skipped reason=not connected kind=\(kind.rawValue) source=\(source)")
            return
        }
        loading = true
        problem = nil
        let asked = kind
        let body: [String: Any] = ["p_kind": asked.rawValue,
                                   "p_langs": langs.isEmpty || asked == .anime ? NSNull() as Any : langs as Any,
                                   "p_genres": genres.isEmpty ? NSNull() as Any : genres as Any,
                                   "p_limit": 10, "p_exclude": shown]
        FabulaNet.rpc("fabula_refine", body: body) { [weak self] result in
            guard let self, mine == self.ticket else { return }
            self.loading = false
            switch result {
            case .success(let json):
                let list = (json as? [Any] ?? []).compactMap { ($0 as? [String: Any]).flatMap(FabulaFilm.init) }
                var seen = Set(self.shown)
                let batch = Array(list.filter { seen.insert($0.tmdb).inserted }.prefix(10))
                self.shown.append(contentsOf: batch.map(\.tmdb))
                self.films = batch
                self.scores = [:]
                self.problem = batch.isEmpty ? "No \(asked.noun(2)) left for this choice" : nil
                note("fabula refiner fetched kind=\(asked.rawValue) source=\(source) received=\(list.count) added=\(batch.count) shown=\(self.shown.count)")
            case .failure(let error):
                self.problem = error.localizedDescription
                note("fabula refiner fetch failed kind=\(asked.rawValue) source=\(source) error=\(error.localizedDescription) shown=\(self.shown.count)")
            }
        }
    }
}

final class FabulaAI: ObservableObject {
    static let shared = FabulaAI()
    static let ideas = ["Cosy and clever", "Edge of my seat", "Make me cry", "Something weird"]

    @Published var mood = ""
    @Published var tune = ""
    @Published private(set) var active = false
    @Published private(set) var thread: [String] = []
    @Published private(set) var films: [FabulaFilm] = []
    @Published private(set) var chosen: Int?
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    @Published private(set) var round = 0

    private var text = ""
    private var asked: FabulaKind = .movie
    private var notes: [String] = []
    private var shown: [Int] = []
    private var ticket = 0

    private init() {}

    var pick: FabulaFilm? { films.first { $0.tmdb == chosen } }

    func find() {
        let value = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        text = value
        asked = FabulaDeck.shared.kind
        notes = []
        shown = []
        thread = [value]
        films = []
        chosen = nil
        round = 0
        active = true
        note("fabula ai started kind=\(asked.rawValue) moodLength=\(value.count)")
        run(source: "mood")
    }

    func send() {
        let value = tune.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, !loading, !value.isEmpty else { return }
        notes.append(value)
        thread.append(value)
        tune = ""
        run(source: "note")
    }

    func reject() {
        guard active, !loading else { return }
        thread.append("None of these")
        run(source: "none")
    }

    func choose(_ film: FabulaFilm) {
        chosen = chosen == film.tmdb ? nil : film.tmdb
    }

    func watch(source: String) {
        guard let film = pick else { return }
        note("fabula ai watch tmdb=\(film.tmdb) round=\(round)")
        FabulaDeck.shared.superlike(film, source: source)
    }

    func leave() {
        ticket += 1
        active = false
        loading = false
        problem = nil
        note("fabula ai left round=\(round)")
    }

    private func run(source: String) {
        ticket += 1
        let mine = ticket
        let before = (films, round)
        round += 1
        chosen = nil
        films = []
        problem = nil
        guard FabulaNet.connected else {
            films = before.0
            round = before.1
            problem = "Cloud not connected"
            note("fabula ai skipped reason=not connected source=\(source)")
            return
        }
        loading = true
        let body: [String: Any] = ["action": "mood", "kind": asked.rawValue, "text": text, "notes": notes, "shown": shown]
        FabulaNet.function("fabula-ai", body: body, timeout: 60) { [weak self] result in
            guard let self, mine == self.ticket else { return }
            self.loading = false
            switch result {
            case .success(let json):
                let list = ((json as? [String: Any])?["films"] as? [Any] ?? []).compactMap { ($0 as? [String: Any]).flatMap(FabulaFilm.init) }
                var seen = Set<Int>()
                let picks = Array(list.filter { seen.insert($0.tmdb).inserted }.prefix(4))
                for film in picks where !self.shown.contains(film.tmdb) { self.shown.append(film.tmdb) }
                self.films = picks
                self.problem = picks.isEmpty ? "No \(self.asked.noun(2)) this round" : nil
                note("fabula ai round done kind=\(self.asked.rawValue) source=\(source) round=\(self.round) films=\(picks.count) notes=\(self.notes.count) shown=\(self.shown.count)")
            case .failure(let error):
                self.films = before.0
                self.round = before.1
                self.problem = error.localizedDescription
                note("fabula ai round failed kind=\(self.asked.rawValue) source=\(source) round=\(self.round) error=\(error.localizedDescription)")
            }
        }
    }
}
