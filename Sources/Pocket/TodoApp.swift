import AppKit
import SwiftUI

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var done = false
    var created = Date()
}

final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published var focusTick = 0
    @Published var showDone = true
    var onNextChange: (() -> Void)?

    let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("Pocket", isDirectory: true).appendingPathComponent("todos.json")
    }

    var open: [TodoItem] { items.filter { !$0.done } }
    var finished: [TodoItem] { items.filter(\.done) }
    var next: TodoItem? { items.first { !$0.done } }

    func load() {
        let files = FileManager.default
        guard files.fileExists(atPath: fileURL.path) else {
            note("pocket todo load none path=\(fileURL.path) count=0")
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = ordered(try decoder.decode([TodoItem].self, from: Data(contentsOf: fileURL)))
            note("pocket todo loaded path=\(fileURL.path) count=\(items.count) open=\(open.count)")
        } catch {
            note("pocket todo load failed path=\(fileURL.path) cause=\(error)")
        }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { $0.append(TodoItem(title: trimmed)) }
    }

    func toggle(_ id: UUID) {
        mutate { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            var item = list.remove(at: index)
            item.done.toggle()
            list.append(item)
        }
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { list in
            guard let index = list.firstIndex(where: { $0.id == id }), list[index].title != trimmed else { return }
            list[index].title = trimmed
        }
    }

    func remove(_ id: UUID) {
        mutate { $0.removeAll { $0.id == id } }
    }

    func moveOpen(from source: IndexSet, to destination: Int) {
        mutate { list in
            var open = list.filter { !$0.done }
            open.move(fromOffsets: source, toOffset: destination)
            list = open + list.filter(\.done)
        }
    }

    func clearDone() {
        let count = items.filter(\.done).count
        guard count > 0 else { return }
        note("pocket todo clear done count=\(count)")
        mutate { $0.removeAll(where: \.done) }
    }

    private func ordered(_ list: [TodoItem]) -> [TodoItem] {
        list.filter { !$0.done } + list.filter(\.done)
    }

    private func mutate(_ change: (inout [TodoItem]) -> Void) {
        let before = items
        let previousNext = next
        var working = items
        change(&working)
        working = ordered(working)
        guard working != before else { return }
        items = working
        save()
        if next != previousNext { onNextChange?() }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            note("pocket todo save failed path=\(fileURL.path) count=\(items.count) cause=\(error)")
        }
    }
}

struct TodoRow: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button { store.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            if editing {
                TextField("Task", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($editFocused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: editFocused) { _, focused in
                        if !focused && editing { commit() }
                    }
            } else {
                Text(item.title)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    .opacity(item.done ? 0.6 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEditing() }
            }

            Spacer(minLength: 0)

            Button { store.remove(item.id) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Delete")
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
    }

    private func beginEditing() {
        guard !item.done else { return }
        draft = item.title
        editing = true
        editFocused = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        store.rename(item.id, to: draft)
    }
}

struct TodoView: View {
    @ObservedObject var store: TodoStore
    @State private var text = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Add a task", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($addFocused)
                .onSubmit {
                    store.add(text)
                    text = ""
                    addFocused = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 10)

            if store.items.isEmpty {
                Spacer()
                Text("Nothing to do. Add a task above.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(store.open) { item in
                        TodoRow(item: item, store: store)
                    }
                    .onMove { store.moveOpen(from: $0, to: $1) }

                    if !store.finished.isEmpty {
                        doneHeader
                        if store.showDone {
                            ForEach(store.finished) { item in
                                TodoRow(item: item, store: store)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { addFocused = true }
        .onChange(of: store.focusTick) { _, _ in addFocused = true }
    }

    private var doneHeader: some View {
        HStack {
            Button { store.showDone.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.showDone ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Done (\(store.finished.count))")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Clear done") { store.clearDone() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .moveDisabled(true)
    }
}

final class TodoApp: PocketApp {
    private static let rotateEvery: TimeInterval = 60
    private let store = TodoStore()
    private var rotation = 0
    private var rotator: Timer?

    override init(spec: AppSpec) {
        super.init(spec: spec)
        store.onNextChange = { [weak self] in self?.changed() }
    }

    override var defaultSize: NSSize { NSSize(width: 380, height: 480) }
    override var resizable: Bool { false }

    override func start() {
        store.load()
        changed()
        let timer = Timer(timeInterval: Self.rotateEvery, repeats: true) { [weak self] _ in self?.rotate() }
        RunLoop.main.add(timer, forMode: .common)
        rotator = timer
        note("todo bar rotation started every=\(Int(Self.rotateEvery))s open=\(store.open.count)")
    }

    private func rotate() {
        guard store.open.count > 1 else { return }
        rotation = (rotation + 1) % store.open.count
        changed()
    }

    override func makeContent() -> NSView {
        NSHostingView(rootView: TodoView(store: store))
    }

    override func didShow() {
        store.focusTick += 1
    }

    override func barTitle() -> NSAttributedString? {
        let open = store.open
        guard !open.isEmpty else { return nil }
        let title = open[rotation % open.count].title.replacingOccurrences(of: "\n", with: " ")
        let shown = title.count > 28 ? String(title.prefix(27)).trimmingCharacters(in: .whitespaces) + "…" : title
        return NSAttributedString(string: shown, attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
    }
}
