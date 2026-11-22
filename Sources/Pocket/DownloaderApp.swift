import AppKit
import SwiftUI

final class DownloaderDraft: ObservableObject {
    @Published var link = ""
    @Published var focusTick = 0
}

struct DownloaderView: View {
    @ObservedObject var model: DownloaderModel
    @ObservedObject var draft: DownloaderDraft
    @ObservedObject var themes = BoardThemeStore.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Paste a link or a Copy as cURL command", text: $draft.link)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Board.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Board.column))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Board.line))
                    .focused($fieldFocused)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Board.theme.isDark ? Board.backdrop : Color.white)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Board.accent))
                }
                .buttonStyle(.plain)
                .disabled(draft.link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let problem = model.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Board.muted)
                    .textSelection(.enabled)
            }
            if model.items.isEmpty {
                Spacer()
                Text("Nothing downloading")
                    .font(.system(size: 12))
                    .foregroundStyle(Board.faint)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.items) { item in
                            DownloadRow(item: item, model: model)
                        }
                    }
                }
                if model.items.contains(where: \.finished) {
                    HStack {
                        Spacer()
                        Button("Clear finished") { model.clearFinished() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(Board.muted)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .id(themes.theme.id)
        .background(Board.backdrop)
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
        .onAppear { fieldFocused = true }
        .onChange(of: draft.focusTick) { fieldFocused = true }
    }

    private func submit() {
        let link = draft.link
        guard !link.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if model.add(link) { draft.link = "" }
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    let model: DownloaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if item.status == "active" || item.status == "waiting" {
                    icon("pause.fill") { model.pause(item) }
                } else if item.status == "paused" {
                    icon("play.fill") { model.resume(item) }
                }
                if item.status == "complete" {
                    icon("magnifyingglass") { model.reveal(item) }
                }
                icon("xmark") { model.remove(item) }
            }
            ProgressView(value: item.fraction)
                .progressViewStyle(.linear)
                .tint(item.status == "error" ? Color(red: 0.86, green: 0.55, blue: 0.55) : Board.accent)
            Text(detail)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Board.muted)
                .lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Board.column))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Board.line))
    }

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: item.total, countStyle: .file)
        let got = ByteCountFormatter.string(fromByteCount: item.done, countStyle: .file)
        switch item.status {
        case "complete": return "Done · \(size)"
        case "error": return item.error ?? "Failed"
        case "removed": return "Cancelled"
        case "paused": return "Paused · \(got) of \(size)"
        case "waiting": return item.total > 0 ? "Queued · \(got) of \(size)" : "Queued"
        default:
            guard item.total > 0 else { return "Connecting…" }
            let pct = Int(item.fraction * 100)
            let speed = ByteCountFormatter.string(fromByteCount: item.speed, countStyle: .file)
            var text = "\(pct)% · \(got) of \(size) · \(speed)/s"
            if item.speed > 0 {
                let left = Double(item.total - item.done) / Double(item.speed)
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = left >= 3600 ? [.hour, .minute] : [.minute, .second]
                formatter.unitsStyle = .abbreviated
                if let eta = formatter.string(from: left) { text += " · \(eta) left" }
            }
            return text
        }
    }

    private func icon(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Board.muted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

final class DownloaderApp: PocketApp {
    private let model = DownloaderModel()
    private let draft = DownloaderDraft()

    override var defaultSize: NSSize { NSSize(width: 380, height: 360) }
    override var minSize: NSSize { NSSize(width: 320, height: 220) }

    override func makeContent() -> NSView {
        ThemedHostingView(rootView: DownloaderView(model: model, draft: draft))
    }

    override func start() {
        model.onChange = { [weak self] in self?.changed() }
        model.start()
        changed()
    }

    override func didShow() {
        model.ensureRunning()
        prefillFromClipboard()
        draft.focusTick += 1
    }

    private func prefillFromClipboard() {
        guard draft.link.isEmpty else {
            note("downloader prefill skipped reason=field-not-empty")
            return
        }
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            note("downloader prefill skipped reason=clipboard-empty")
            return
        }
        if clip.hasPrefix("curl "), let curl = CurlCommand.parse(clip) {
            draft.link = clip
            note("downloader prefilled curl from clipboard host=\(URL(string: curl.url)?.host ?? "?")")
            return
        }
        guard !clip.contains(" "), !clip.contains("\n"), let url = URL(string: clip), let scheme = url.scheme?.lowercased(),
              ["http", "https", "ftp", "magnet"].contains(scheme) else {
            note("downloader prefill skipped reason=not-a-link length=\(clip.count)")
            return
        }
        draft.link = clip
        note("downloader prefilled link from clipboard host=\(url.host ?? scheme)")
    }

    func remoteAdd(_ link: String, source: String) -> Bool {
        note("downloader remote add source=\(source)")
        return model.add(link)
    }

    func remoteState() -> [String: Any] {
        var state: [String: Any] = ["downloads": model.items.map { item in
            ["id": item.id, "name": item.name, "status": item.status, "total": item.total, "done": item.done,
             "speed": item.speed, "error": item.error ?? NSNull(), "path": item.path ?? NSNull()] as [String: Any]
        }]
        state["percent"] = model.percent ?? NSNull()
        state["problem"] = model.problem ?? NSNull()
        return state
    }

    override func barImage() -> NSImage? {
        model.percent == nil ? AppIcon.render(spec) : nil
    }

    override func barTitle() -> NSAttributedString? {
        guard let percent = model.percent else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
        ]
        return NSAttributedString(string: "\(percent)%", attributes: attributes)
    }

    override func stop() {
        model.stop()
        super.stop()
    }
}
