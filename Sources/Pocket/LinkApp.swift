import AppKit

final class LinkApp: PocketApp {
    let url: URL

    init(spec: AppSpec, url: URL) {
        self.url = url
        super.init(spec: spec)
    }

    override func toggle(anchor: NSStatusItem?, source: String) {
        AppDelegate.shared.hideOthers(except: self)
        let id = spec.id
        let target = url
        guard let browser = spec.browser, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) else {
            if let browser = spec.browser { note("pocket link browser missing app=\(id) browser=\(browser) fallback=default") }
            let opened = NSWorkspace.shared.open(target)
            note("pocket link opened app=\(id) url=\(target.absoluteString) browser=default source=\(source) ok=\(opened)")
            return
        }
        NSWorkspace.shared.open([target], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                note("pocket link open failed app=\(id) url=\(target.absoluteString) browser=\(browser) error=\(error.localizedDescription)")
            } else {
                note("pocket link opened app=\(id) url=\(target.absoluteString) browser=\(browser) source=\(source)")
            }
        }
    }
}
