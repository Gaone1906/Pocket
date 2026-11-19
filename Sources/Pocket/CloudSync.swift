import Foundation

struct CloudCollection {
    let kind: String
    let key: String?
    let sortKey: String?
}

struct CloudDocument {
    let name: String
    let file: URL
    let collections: [CloudCollection]
    let metaKind: String?

    var isArray: Bool { collections.count == 1 && collections[0].key == nil }

    static var all: [CloudDocument] {
        [CloudDocument(name: "board", file: PocketData.board,
                       collections: [CloudCollection(kind: "board.project", key: "projects", sortKey: "_pos"),
                                     CloudCollection(kind: "board.session", key: "sessions", sortKey: "ended")],
                       metaKind: nil),
         CloudDocument(name: "schedule", file: PocketData.schedule,
                       collections: [CloudCollection(kind: "schedule.routine", key: "routines", sortKey: "_pos"),
                                     CloudCollection(kind: "schedule.check", key: "checks", sortKey: nil)],
                       metaKind: "schedule.settings"),
         CloudDocument(name: "runner", file: PocketData.runner,
                       collections: [CloudCollection(kind: "runner.entry", key: "entries", sortKey: nil)],
                       metaKind: nil),
         CloudDocument(name: "calorie", file: PocketData.calorie,
                       collections: [CloudCollection(kind: "calorie.entry", key: "entries", sortKey: nil),
                                     CloudCollection(kind: "calorie.weight", key: "weights", sortKey: nil)],
                       metaKind: "calorie.settings")]
    }
}

private struct CloudRow {
    let kind: String
    let id: String
    let data: [String: Any]
    let deleted: Bool
    let updatedAt: String
}

private struct CloudFailure: Error {
    let status: Int
    let message: String
}

final class CloudSync: ObservableObject {
    static let shared = CloudSync()
    static let urlKey = "pocket.cloud.url"
    static let anonKey = "pocket.cloud.key"
    static let deviceKey = "pocket.cloud.device"
    private static let sharedUser = "00000000-0000-0000-0000-000000000000"
    private static let metaId = "book"

    @Published private(set) var lastSync: Date?
    @Published private(set) var problem: String?

    private let queue = DispatchQueue(label: "pocket.cloud", qos: .utility)
    private let session = URLSession(configuration: .ephemeral)
    private var adopters: [String: (Data) -> Void] = [:]
    private var pending = false
    private var poller: Timer?
    private var stateFile: URL { PocketData.root.appendingPathComponent("cloud-state.json") }

    private init() {}

    var baseURL: String? {
        UserDefaults.standard.string(forKey: Self.urlKey).flatMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
    }

    var key: String? { UserDefaults.standard.string(forKey: Self.anonKey).flatMap { $0.isEmpty ? nil : $0 } }
    var device: String { UserDefaults.standard.string(forKey: Self.deviceKey) ?? Host.current().localizedName ?? "Mac" }
    var configured: Bool { baseURL != nil && key != nil }
    var signedIn: Bool { configured }

    func register(_ name: String, adopt: @escaping (Data) -> Void) {
        adopters[name] = adopt
    }

    func start() {
        note("pocket cloud started url=\(baseURL ?? "none") configured=\(configured)")
        guard signedIn else { return }
        schedule(after: 5)
        poller?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.schedule(after: 0) }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    func schedule(after delay: TimeInterval) {
        guard signedIn else { return }
        queue.async { [self] in
            guard !pending else { return }
            pending = true
            queue.asyncAfter(deadline: .now() + delay) { [self] in
                pending = false
                sync()
            }
        }
    }

    func syncNow() {
        queue.async { [self] in sync() }
    }

    func status() -> [String: Any] {
        var out: [String: Any] = ["configured": configured, "signedIn": signedIn, "device": device]
        out["url"] = baseURL ?? NSNull()
        out["lastSync"] = lastSync.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        out["problem"] = problem ?? NSNull()
        return out
    }

    func connect(link: String) throws {
        guard let range = link.range(of: "connect=") else { throw CloudFailure(status: 400, message: "that is not a Pocket setup link") }
        let raw = String(link[range.upperBound...]).components(separatedBy: "&")[0]
        guard let decoded = raw.removingPercentEncoding,
              let data = Data(base64Encoded: decoded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["url"] as? String, !url.isEmpty,
              let key = json["key"] as? String, !key.isEmpty
        else { throw CloudFailure(status: 400, message: "the setup link could not be read") }
        UserDefaults.standard.set(url, forKey: Self.urlKey)
        UserDefaults.standard.set(key, forKey: Self.anonKey)
        try? FileManager.default.removeItem(at: stateFile)
        note("pocket cloud connected url=\(url)")
        DispatchQueue.main.async { self.start() }
    }

    func disconnect() {
        queue.async { [self] in
            UserDefaults.standard.removeObject(forKey: Self.urlKey)
            UserDefaults.standard.removeObject(forKey: Self.anonKey)
            try? FileManager.default.removeItem(at: stateFile)
            DispatchQueue.main.async {
                self.poller?.invalidate()
                self.poller = nil
                self.lastSync = nil
                note("pocket cloud disconnected")
            }
        }
    }

    private func call(_ method: String, _ path: String, body: Any? = nil, prefer: String? = nil) throws -> Any? {
        guard let base = baseURL, let key, let url = URL(string: base + path) else { throw CloudFailure(status: 409, message: "cloud not configured") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.hasPrefix("sb_") { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let done = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        session.dataTask(with: request) { data, response, error in
            result = (data, response, error)
            done.signal()
        }.resume()
        done.wait()
        if let error = result.2 { throw CloudFailure(status: 0, message: error.localizedDescription) }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        let json = result.0.flatMap { $0.isEmpty ? nil : try? JSONSerialization.jsonObject(with: $0) }
        guard (200..<300).contains(status) else {
            let info = json as? [String: Any]
            let message = (info?["msg"] ?? info?["message"] ?? info?["error_description"] ?? info?["error"]) as? String
            throw CloudFailure(status: status, message: message ?? "HTTP \(status)")
        }
        return json
    }

    private struct SyncState: Codable {
        var cursor: String
        var seen: [String: String]
        var docs: [String]?
    }

    private func loadState() -> SyncState {
        guard let data = try? Data(contentsOf: stateFile), let state = try? JSONDecoder().decode(SyncState.self, from: data) else {
            return SyncState(cursor: "1970-01-01T00:00:00Z", seen: [:])
        }
        return state
    }

    private func saveState(_ state: SyncState) {
        do {
            try JSONEncoder().encode(state).write(to: stateFile, options: .atomic)
        } catch {
            note("pocket cloud state save failed path=\(stateFile.path) error=\(error.localizedDescription)")
        }
    }

    private static func canonical(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func identifier(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func read(_ doc: CloudDocument) -> Any? {
        guard let data = try? Data(contentsOf: doc.file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func records(of doc: CloudDocument, in json: Any) -> [String: (kind: String, id: String, data: [String: Any])] {
        var out: [String: (kind: String, id: String, data: [String: Any])] = [:]
        for collection in doc.collections {
            let items: [Any]
            if collection.key == nil {
                items = json as? [Any] ?? []
            } else {
                items = ((json as? [String: Any])?[collection.key!] as? [Any]) ?? []
            }
            for (index, element) in items.enumerated() {
                guard var item = element as? [String: Any], let id = identifier(item["id"]) else { continue }
                if collection.sortKey == "_pos" { item["_pos"] = index + 1 }
                out[collection.kind + "|" + id] = (collection.kind, id, item)
            }
        }
        if let meta = doc.metaKind, let object = json as? [String: Any] {
            let keys = Set(doc.collections.compactMap(\.key))
            let rest = object.filter { !keys.contains($0.key) }
            if !rest.isEmpty { out[meta + "|" + metaId] = (meta, metaId, rest) }
        }
        return out
    }

    private static func sortValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String {
            if let date = ISO8601DateFormatter().date(from: text) { return date.timeIntervalSince1970 }
            return Double(text)
        }
        return nil
    }

    private static func apply(_ rows: [CloudRow], to doc: CloudDocument, base: Any?) -> Data? {
        var lists: [String: [[String: Any]]] = [:]
        var object = (base as? [String: Any]) ?? [:]
        for collection in doc.collections {
            let items: [Any] = collection.key == nil ? (base as? [Any] ?? []) : (object[collection.key!] as? [Any] ?? [])
            lists[collection.kind] = items.compactMap { $0 as? [String: Any] }
        }
        for row in rows {
            if row.kind == doc.metaKind {
                guard !row.deleted else { continue }
                for (key, value) in row.data where !doc.collections.contains(where: { $0.key == key }) { object[key] = value }
                continue
            }
            guard var list = lists[row.kind] else { continue }
            let index = list.firstIndex { identifier($0["id"]) == row.id }
            if row.deleted {
                if let index { list.remove(at: index) }
            } else if let index {
                list[index] = row.data
            } else {
                list.append(row.data)
            }
            lists[row.kind] = list
        }
        for collection in doc.collections {
            var list = lists[collection.kind] ?? []
            if let sortKey = collection.sortKey {
                let original = Dictionary(list.enumerated().map { (identifier($0.element["id"]) ?? "", Double($0.offset + 1)) }, uniquingKeysWith: { first, _ in first })
                list = list.enumerated().sorted { a, b in
                    let left = sortValue(a.element[sortKey]) ?? original[identifier(a.element["id"]) ?? ""] ?? Double(a.offset)
                    let right = sortValue(b.element[sortKey]) ?? original[identifier(b.element["id"]) ?? ""] ?? Double(b.offset)
                    return left == right ? a.offset < b.offset : left < right
                }.map(\.element)
            }
            let stripped: [[String: Any]] = list.map { item in
                var copy = item
                copy.removeValue(forKey: "_pos")
                return copy
            }
            if collection.key == nil {
                return try? JSONSerialization.data(withJSONObject: stripped, options: [.prettyPrinted, .sortedKeys])
            }
            object[collection.key!] = stripped
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func pull(since cursor: String) throws -> [CloudRow] {
        let overlap: String = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            let trimmed = cursor.replacingOccurrences(of: #"\.(\d{3})\d*"#, with: ".$1", options: .regularExpression)
            let date = formatter.date(from: trimmed) ?? plain.date(from: cursor) ?? Date(timeIntervalSince1970: 0)
            return plain.string(from: date.addingTimeInterval(-120))
        }()
        var rows: [CloudRow] = []
        var offset = 0
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:")
        let since = overlap.addingPercentEncoding(withAllowedCharacters: allowed) ?? overlap
        while true {
            let page = try call("GET", "/rest/v1/records?select=kind,id,data,deleted,updated_at&updated_at=gt.\(since)&order=updated_at.asc&limit=1000&offset=\(offset)") as? [[String: Any]] ?? []
            for item in page {
                guard let kind = item["kind"] as? String, let id = item["id"] as? String else { continue }
                rows.append(CloudRow(kind: kind, id: id, data: item["data"] as? [String: Any] ?? [:], deleted: item["deleted"] as? Bool ?? false, updatedAt: item["updated_at"] as? String ?? cursor))
            }
            if page.count < 1000 { break }
            offset += page.count
        }
        return rows
    }

    private func sync() {
        guard signedIn else { return }
        do {
            var state = loadState()
            let docs = CloudDocument.all
            let known = Set(state.docs ?? ["board", "schedule"])
            let added = docs.map(\.name).filter { !known.contains($0) }
            if !added.isEmpty {
                note("pocket cloud full pull reason=new documents names=\(added.joined(separator: ",")) cursor=\(state.cursor)")
                state.cursor = "1970-01-01T00:00:00Z"
            }
            state.docs = docs.map(\.name)
            let before = Dictionary(uniqueKeysWithValues: docs.map { doc in (doc.name, Self.read(doc).map { Self.records(of: doc, in: $0) }) })
            var changedHere = Set<String>()
            for doc in docs {
                guard let local = before[doc.name] ?? nil else { continue }
                for (key, record) in local where state.seen[key] != Self.canonical(record.data) { changedHere.insert(key) }
            }
            let rows = try pull(since: state.cursor)
            var newest = state.cursor
            var incoming: [String: [CloudRow]] = [:]
            for row in rows {
                if row.updatedAt > newest { newest = row.updatedAt }
                let key = row.kind + "|" + row.id
                if changedHere.contains(key) { continue }
                let current = state.seen[key]
                if row.deleted ? current == nil : current == Self.canonical(row.data) { continue }
                guard let doc = docs.first(where: { $0.metaKind == row.kind || $0.collections.contains { $0.kind == row.kind } }) else { continue }
                incoming[doc.name, default: []].append(row)
            }
            for doc in docs {
                guard let list = incoming[doc.name], !list.isEmpty else { continue }
                DispatchQueue.main.sync {
                    guard let data = Self.apply(list, to: doc, base: Self.read(doc)) else {
                        note("pocket cloud apply failed name=\(doc.name) rows=\(list.count)")
                        return
                    }
                    if let adopter = adopters[doc.name] {
                        adopter(data)
                    } else {
                        do {
                            try FileManager.default.createDirectory(at: doc.file.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try data.write(to: doc.file, options: .atomic)
                            DataVault.shared.snapshot(data, name: doc.name, count: -1)
                        } catch {
                            note("pocket cloud write failed name=\(doc.name) path=\(doc.file.path) error=\(error.localizedDescription)")
                        }
                    }
                }
                for row in list {
                    let key = row.kind + "|" + row.id
                    if row.deleted { state.seen.removeValue(forKey: key) } else { state.seen[key] = Self.canonical(row.data) }
                }
                note("pocket cloud applied name=\(doc.name) rows=\(list.count) deleted=\(list.filter(\.deleted).count)")
            }
            var upserts: [[String: Any]] = []
            var marks: [(String, String?)] = []
            for doc in docs {
                guard let json = Self.read(doc) else { continue }
                let local = Self.records(of: doc, in: json)
                for (key, record) in local {
                    let text = Self.canonical(record.data)
                    guard state.seen[key] != text else { continue }
                    upserts.append(["user_id": Self.sharedUser, "kind": record.kind, "id": record.id, "data": record.data, "deleted": false, "device": device])
                    marks.append((key, text))
                }
                let kinds = Set(doc.collections.map(\.kind))
                let gone = state.seen.keys.filter { key in
                    guard let kind = key.split(separator: "|", maxSplits: 1).first.map(String.init), kinds.contains(kind) else { return false }
                    return local[key] == nil
                }
                let tracked = state.seen.keys.filter { key in key.split(separator: "|", maxSplits: 1).first.map { kinds.contains(String($0)) } ?? false }.count
                if !gone.isEmpty, local.isEmpty || (gone.count > 20 && gone.count * 2 > tracked) {
                    note("pocket cloud delete held name=\(doc.name) missing=\(gone.count) tracked=\(tracked) local=\(local.count)")
                    continue
                }
                for key in gone {
                    let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                    upserts.append(["user_id": Self.sharedUser, "kind": parts[0], "id": parts[1], "data": [String: Any](), "deleted": true, "device": device])
                    marks.append((key, nil))
                }
            }
            var start = 0
            while start < upserts.count {
                let chunk = Array(upserts[start..<min(start + 500, upserts.count)])
                _ = try call("POST", "/rest/v1/records?on_conflict=user_id,kind,id", body: chunk, prefer: "resolution=merge-duplicates,return=minimal")
                start += chunk.count
            }
            for (key, text) in marks {
                if let text { state.seen[key] = text } else { state.seen.removeValue(forKey: key) }
            }
            state.cursor = newest
            saveState(state)
            let pulled = rows.count
            let pushed = upserts.count
            DispatchQueue.main.async {
                self.lastSync = Date()
                self.problem = nil
            }
            if pushed > 0 || incoming.values.contains(where: { !$0.isEmpty }) {
                note("pocket cloud synced pulled=\(pulled) applied=\(incoming.values.reduce(0) { $0 + $1.count }) pushed=\(pushed)")
            }
        } catch let failure as CloudFailure {
            note("pocket cloud sync failed status=\(failure.status) error=\(failure.message)")
            DispatchQueue.main.async { self.problem = failure.message }
        } catch {
            note("pocket cloud sync failed error=\(error.localizedDescription)")
            DispatchQueue.main.async { self.problem = error.localizedDescription }
        }
    }
}
