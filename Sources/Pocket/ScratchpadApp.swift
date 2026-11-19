import AppKit
import SwiftUI

struct ScratchPage: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var updated: Date
}

final class ScratchStore: ObservableObject {
    @Published private(set) var pages: [ScratchPage] = []
    @Published var current: UUID?
    let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Pocket/Scratchpad")
    private var index: URL { folder.appendingPathComponent("pages.json") }

    init() {
        load()
        if pages.isEmpty { create() }
        current = current ?? pages.first?.id
    }

    private func load() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: index.path) else { return }
            pages = try JSONDecoder().decode([ScratchPage].self, from: Data(contentsOf: index))
            note("scratchpad loaded pages=\(pages.count)")
        } catch {
            note("scratchpad index load failed path=\(index.path) error=\(error.localizedDescription)")
        }
    }

    private func saveIndex() {
        do {
            try JSONEncoder().encode(pages).write(to: index, options: .atomic)
        } catch {
            note("scratchpad index save failed pages=\(pages.count) error=\(error.localizedDescription)")
        }
    }

    private func file(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).rtf") }

    @discardableResult
    func create() -> UUID {
        let page = ScratchPage(id: UUID(), title: "", updated: Date())
        pages.insert(page, at: 0)
        current = page.id
        saveIndex()
        note("scratchpad page created page=\(page.id) total=\(pages.count)")
        return page.id
    }

    func delete(_ id: UUID) {
        pages.removeAll { $0.id == id }
        do {
            if FileManager.default.fileExists(atPath: file(id).path) { try FileManager.default.removeItem(at: file(id)) }
        } catch {
            note("scratchpad page file delete failed page=\(id) error=\(error.localizedDescription)")
        }
        if pages.isEmpty { create() }
        if current == id { current = pages.first?.id }
        saveIndex()
        note("scratchpad page deleted page=\(id) remaining=\(pages.count)")
    }

    func text(_ id: UUID) -> NSAttributedString {
        let url = file(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return NSAttributedString() }
        do {
            return try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        } catch {
            note("scratchpad page load failed page=\(id) error=\(error.localizedDescription)")
            return NSAttributedString()
        }
    }

    func save(_ id: UUID, _ text: NSAttributedString) {
        do {
            let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: file(id), options: .atomic)
        } catch {
            note("scratchpad page save failed page=\(id) chars=\(text.length) error=\(error.localizedDescription)")
            return
        }
        let title = text.string.split(whereSeparator: \.isNewline).lazy
            .map { $0.replacingOccurrences(of: "^\\t[^\\t]*\\t", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard let at = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[at].title = String(title.prefix(60))
        pages[at].updated = Date()
        saveIndex()
    }
}

enum ScratchFormat {
    static let bodySize: CGFloat = 13
    static let headingSize: CGFloat = 19
    static let bullet = NSTextList.MarkerFormat.disc
    static let numbered = NSTextList.MarkerFormat("{decimal}.")
    static let check = NSTextList.MarkerFormat.hyphen

    static var body: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: bodySize), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph(nil)]
    }

    static func paragraph(_ list: NSTextList?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 3
        if let list {
            style.textLists = [list]
            style.tabStops = [NSTextTab(textAlignment: .right, location: 18), NSTextTab(textAlignment: .left, location: 26)]
            style.headIndent = 26
        }
        return style
    }
}

final class ScratchTextView: NSTextView {
    var onChange: (() -> Void)?

    func toggleTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        let manager = NSFontManager.shared
        if range.length == 0 {
            let font = typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: ScratchFormat.bodySize)
            let has = manager.traits(of: font).contains(trait)
            typingAttributes[.font] = has ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            return
        }
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? NSFont, !manager.traits(of: font).contains(trait) { allHave = false }
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: ScratchFormat.bodySize)
            storage.addAttribute(.font, value: allHave ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait), range: sub)
        }
        storage.endEditing()
        didChangeText()
    }

    func toggleAttribute(_ key: NSAttributedString.Key) {
        let range = selectedRange()
        if range.length == 0 {
            let on = (typingAttributes[key] as? Int ?? 0) != 0
            typingAttributes[key] = on ? nil : NSUnderlineStyle.single.rawValue
            return
        }
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        var allOn = true
        storage.enumerateAttribute(key, in: range) { value, _, _ in if (value as? Int ?? 0) == 0 { allOn = false } }
        storage.beginEditing()
        if allOn {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        storage.endEditing()
        didChangeText()
    }

    func toggleHeading() {
        guard let storage = textStorage else { return }
        let range = (string as NSString).paragraphRange(for: selectedRange())
        let probe = range.length > 0 ? range.location : max(0, range.location - 1)
        let current = (storage.length > 0 ? storage.attribute(.font, at: min(probe, storage.length - 1), effectiveRange: nil) : nil) as? NSFont
        let isHeading = (current?.pointSize ?? 0) >= ScratchFormat.headingSize
        let font = isHeading ? NSFont.systemFont(ofSize: ScratchFormat.bodySize) : NSFont.systemFont(ofSize: ScratchFormat.headingSize, weight: .bold)
        if range.length > 0, shouldChangeText(in: range, replacementString: nil) {
            storage.addAttribute(.font, value: font, range: range)
            didChangeText()
        }
        typingAttributes[.font] = font
    }

    func toggleList(_ format: NSTextList.MarkerFormat) {
        guard let storage = textStorage else { return }
        let text = string as NSString
        let range = text.paragraphRange(for: selectedRange())
        var paragraphs: [NSRange] = []
        text.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in paragraphs.append(enclosing) }
        if paragraphs.isEmpty { paragraphs = [range] }
        let probe = min(range.location, max(0, storage.length - 1))
        let existing = storage.length > 0 ? (storage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first : (typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.first
        let removing = existing?.markerFormat == format
        let list = NSTextList(markerFormat: format, options: 0)
        let rebuilt = NSMutableAttributedString()
        for (number, paragraph) in paragraphs.enumerated() {
            let line = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: paragraph))
            let hadList = line.length > 0 && !((line.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textLists.isEmpty ?? true)
            if hadList, let marker = line.string.range(of: "^\\t[^\\t\\n]*\\t", options: .regularExpression) {
                line.deleteCharacters(in: NSRange(marker, in: line.string))
            }
            var attributes = line.length > 0 ? line.attributes(at: 0, effectiveRange: nil) : typingAttributes
            attributes[.paragraphStyle] = ScratchFormat.paragraph(removing ? nil : list)
            if !removing {
                line.insert(NSAttributedString(string: "\t\(list.marker(forItemNumber: number + 1))\t", attributes: attributes), at: 0)
            }
            line.addAttribute(.paragraphStyle, value: ScratchFormat.paragraph(removing ? nil : list), range: NSRange(location: 0, length: line.length))
            rebuilt.append(line)
        }
        guard shouldChangeText(in: range, replacementString: rebuilt.string) else { return }
        storage.replaceCharacters(in: range, with: rebuilt)
        didChangeText()
        let end = range.location + rebuilt.length - (rebuilt.string.hasSuffix("\n") ? 1 : 0)
        setSelectedRange(NSRange(location: end, length: 0))
        typingAttributes[.paragraphStyle] = ScratchFormat.paragraph(removing ? nil : list)
    }

    func applyShortcutAfterSpace() -> Bool {
        let text = string as NSString
        let caret = selectedRange().location
        let lineStart = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
        let prefix = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let format: NSTextList.MarkerFormat?
        switch prefix {
        case "-", "*", "•": format = ScratchFormat.bullet
        case "1.", "1)": format = ScratchFormat.numbered
        case "#":
            replaceCharacters(in: NSRange(location: lineStart, length: prefix.count), with: "")
            toggleHeading()
            return true
        default: format = nil
        }
        guard let format, shouldChangeText(in: NSRange(location: lineStart, length: prefix.count), replacementString: "") else { return false }
        textStorage?.replaceCharacters(in: NSRange(location: lineStart, length: prefix.count), with: "")
        didChangeText()
        setSelectedRange(NSRange(location: lineStart, length: 0))
        toggleList(format)
        return true
    }
}

struct ScratchEditor: NSViewRepresentable {
    @ObservedObject var store: ScratchStore
    let attach: (ScratchTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = ScratchTextView(usingTextLayoutManager: false)
        view.isRichText = true
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 14, height: 12)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.typingAttributes = ScratchFormat.body
        view.insertionPointColor = NSColor(Board.accentInk)
        view.delegate = context.coordinator
        scroll.documentView = view
        context.coordinator.view = view
        attach(view)
        context.coordinator.show(store.current)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? NSTextView)?.insertionPointColor = NSColor(Board.accentInk)
        if context.coordinator.loaded != store.current { context.coordinator.show(store.current) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: ScratchStore
        weak var view: ScratchTextView?
        var loaded: UUID?
        var pending: DispatchWorkItem?

        init(store: ScratchStore) { self.store = store }

        func show(_ id: UUID?) {
            flush()
            guard let view, let id else { return }
            loaded = id
            view.textStorage?.setAttributedString(store.text(id))
            view.typingAttributes = ScratchFormat.body
            view.undoManager?.removeAllActions()
            view.setSelectedRange(NSRange(location: view.string.count, length: 0))
            view.window?.makeFirstResponder(view)
        }

        func flush() {
            pending?.cancel()
            pending = nil
            guard let view, let loaded, let text = view.textStorage else { return }
            store.save(loaded, NSAttributedString(attributedString: text))
        }

        func textDidChange(_ notification: Notification) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard text == " ", range.length == 0, let view = textView as? ScratchTextView else { return true }
            return !view.applyShortcutAfterSpace()
        }
    }
}

struct ScratchView: View {
    @ObservedObject var store: ScratchStore
    @ObservedObject var themes = BoardThemeStore.shared
    @State private var editor: ScratchTextView?
    @State private var hovered: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("PAGES").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Board.muted)
                    Spacer()
                    Button { store.create() } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Board.muted)
                        .help("New page")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.pages) { page in row(page) }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.top, 34)
            .frame(width: 150)
            .background(themes.theme.panel)
            Rectangle().fill(Board.line).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Board.line).frame(height: 1)
                ScratchEditor(store: store) { view in DispatchQueue.main.async { editor = view } }
            }
        }
        .background(BoardBackdrop(theme: themes.theme))
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
        .tint(themes.theme.accent)
    }

    func row(_ page: ScratchPage) -> some View {
        let selected = store.current == page.id
        return Button { store.current = page.id } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title.isEmpty ? "New page" : page.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(page.title.isEmpty ? Board.muted : Board.ink)
                    .lineLimit(1)
                Text(page.updated, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(Board.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Board.accent.opacity(themes.theme.isDark ? 0.24 : 0.2) : hovered == page.id ? Board.ink.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? page.id : (hovered == page.id ? nil : hovered) }
        .contextMenu {
            Button("Delete page", role: .destructive) { store.delete(page.id) }
        }
    }

    var toolbar: some View {
        HStack(spacing: 2) {
            tool("bold", "Bold") { $0.toggleTrait(.boldFontMask) }
            tool("italic", "Italic") { $0.toggleTrait(.italicFontMask) }
            tool("underline", "Underline") { $0.toggleAttribute(.underlineStyle) }
            tool("strikethrough", "Strikethrough") { $0.toggleAttribute(.strikethroughStyle) }
            Divider().frame(height: 16).padding(.horizontal, 6)
            tool("textformat.size", "Heading, or type # and a space") { $0.toggleHeading() }
            tool("list.bullet", "Bulleted list, or type - and a space") { $0.toggleList(ScratchFormat.bullet) }
            tool("list.number", "Numbered list, or type 1. and a space") { $0.toggleList(ScratchFormat.numbered) }
            tool("list.dash", "Dashed list") { $0.toggleList(ScratchFormat.check) }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 30)
        .padding(.bottom, 6)
    }

    func tool(_ symbol: String, _ help: String, _ action: @escaping (ScratchTextView) -> Void) -> some View {
        Button {
            guard let editor else { return }
            editor.window?.makeFirstResponder(editor)
            action(editor)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Board.muted)
        .help(help)
    }
}

final class ScratchpadApp: PocketApp {
    private let store = ScratchStore()
    private weak var editor: ScratchTextView?

    override var defaultSize: NSSize { NSSize(width: 560, height: 520) }
    override var minSize: NSSize { NSSize(width: 440, height: 360) }

    override func makeContent() -> NSView {
        ThemedHostingView(rootView: ScratchView(store: store))
    }

    override func didShow() {
        guard let content = panelIfLoaded?.contentView else { return }
        if let view = find(in: content) { panelIfLoaded?.makeFirstResponder(view) }
    }

    override func didHide() {
        guard let content = panelIfLoaded?.contentView, let view = find(in: content), let delegate = view.delegate as? ScratchEditor.Coordinator else { return }
        delegate.flush()
    }

    private func find(in view: NSView) -> ScratchTextView? {
        if let match = view as? ScratchTextView { return match }
        for child in view.subviews { if let match = find(in: child) { return match } }
        return nil
    }
}
