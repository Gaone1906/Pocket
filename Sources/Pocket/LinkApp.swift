import AppKit

final class LinkApp: PocketApp {
    let url: URL

    init(spec: AppSpec, url: URL) {
        self.url = url
        super.init(spec: spec)
    }

    override func toggle(anchor: NSStatusItem?, source: String) {
        AppDelegate.shared.hideOthers(except: self)
        let opened = NSWorkspace.shared.open(url)
        note("pocket link opened app=\(spec.id) url=\(url.absoluteString) source=\(source) ok=\(opened)")
    }
}
