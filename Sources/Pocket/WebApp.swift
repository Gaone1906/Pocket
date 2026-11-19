import AppKit
import UserNotifications
import WebKit

let notificationShim = """
(() => {
  const post = (title, body, tag) => window.webkit.messageHandlers.pocketNotify.postMessage({ title: String(title || ""), body: String(body || ""), tag: String(tag || "") });
  class PocketNotification extends EventTarget {
    constructor(title, options = {}) {
      super();
      this.title = title;
      this.body = options.body || "";
      this.tag = options.tag || "";
      this.onclick = null;
      this.onclose = null;
      this.onshow = null;
      this.onerror = null;
      post(title, this.body, this.tag);
    }
    close() {}
    static get permission() { return "granted"; }
    static requestPermission(callback) { if (callback) callback("granted"); return Promise.resolve("granted"); }
  }
  Object.defineProperty(window, "Notification", { value: PocketNotification, configurable: true, writable: true });
})();
"""

let mediaScript = """
(() => {
  const seen = new Set();
  const play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) { seen.add(this); return play.apply(this, args); };
  window.__pocketPlaying = () =>
    [...seen, ...document.querySelectorAll("audio,video")].some(m => !m.paused && !m.ended) ||
    navigator.mediaSession?.playbackState === "playing";
})();
"""

let playbackWatch = """
(() => {
  const counts = {};
  const report = (kind, detail, cap = 30) => {
    counts[kind] = (counts[kind] || 0) + 1;
    if (counts[kind] > cap) return;
    try { window.webkit.messageHandlers.pocketWatch.postMessage({ kind: String(kind), detail: String(detail ?? "").slice(0, 300) }); } catch (e) {}
  };
  const watched = /connect-state|track-playback|playback|license|widevine|fairplay|melody|gabo|dealer|spclient/i;
  const bare = url => String(url || "").split("?")[0];
  const nativeFetch = window.fetch;
  window.fetch = function (input, init) {
    const url = typeof input === "string" ? input : (input && input.url) || "";
    return nativeFetch.apply(this, arguments).then(
      response => { if (!response.ok && watched.test(url)) report("http " + response.status, bare(url)); return response; },
      error => { if (watched.test(url)) report("fetch failed", bare(url) + " " + error); throw error; });
  };
  let seen = false;
  let live = 0;
  window.__pocketConnected = () => seen ? live > 0 : null;
  const NativeSocket = window.WebSocket;
  window.WebSocket = class extends NativeSocket {
    constructor(url, protocols) {
      super(url, protocols);
      const host = bare(url);
      const dealer = /dealer/i.test(host);
      let counted = false;
      this.addEventListener("open", () => {
        if (dealer) { seen = true; live += 1; counted = true; }
        report("socket open", host, 100);
      });
      this.addEventListener("close", event => {
        if (counted) { live -= 1; counted = false; }
        report("socket closed", host + " code=" + event.code + " clean=" + event.wasClean, 100);
      });
      this.addEventListener("error", () => report("socket error", host, 100));
    }
  };
  if (navigator.requestMediaKeySystemAccess) {
    const ask = navigator.requestMediaKeySystemAccess.bind(navigator);
    navigator.requestMediaKeySystemAccess = (system, configs) => ask(system, configs).then(
      access => { report("drm granted", system, 5); return access; },
      error => { report("drm refused", system + " " + error, 10); throw error; });
  }
  for (const type of ["error", "stalled", "abort", "emptied"]) {
    document.addEventListener(type, event => {
      if (event.target instanceof HTMLMediaElement) report("media " + type, event.target.error ? event.target.error.code + " " + event.target.error.message : "");
    }, true);
  }
  window.addEventListener("unhandledrejection", event => report("rejection", event.reason && (event.reason.message || event.reason)));
  window.addEventListener("error", event => report("script error", event.message));
  const nativeError = console.error;
  console.error = function (...args) { report("console", args.map(a => a && a.message ? a.message : a).join(" ")); return nativeError.apply(this, args); };
})();
"""

let connectedProbe = "typeof window.__pocketConnected === 'function' ? window.__pocketConnected() : null"

let playingProbe = "typeof window.__pocketPlaying === 'function' && window.__pocketPlaying() === true"

class WebApp: PocketApp, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let site: WebSpec
    let container = NSView()
    var web: WKWebView?
    var titleWatch: NSKeyValueObservation?
    var choosingFile = false
    var healthTimer: Timer?
    var unloadWork: DispatchWorkItem?
    var popups: [ObjectIdentifier: (view: WKWebView, window: NSWindow)] = [:]
    var unread = 0 {
        didSet {
            guard unread != oldValue else { return }
            note("pocket unread app=\(spec.id) count=\(unread)")
            changed()
        }
    }

    init(spec: AppSpec, site: WebSpec) {
        self.site = site
        super.init(spec: spec)
    }

    override func barImage() -> NSImage? { AppIcon.render(spec, unread: unread) }

    override func makeContent() -> NSView { container }

    override func start() {
        _ = panel
        guard site.unloadAfter == nil else { return note("pocket deferred app=\(spec.id) until first open") }
        load(reason: "startup")
    }

    func load(reason: String) {
        guard web == nil else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: site.store)
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.inactiveSchedulingPolicy = site.realtime ? .none : .throttle
        if site.realtime {
            for key in ["pageVisibilityBasedProcessSuppressionEnabled", "hiddenPageDOMTimerThrottlingEnabled", "hiddenPageDOMTimerThrottlingAutoIncreases"]
            where config.preferences.responds(to: NSSelectorFromString("_set\(key.prefix(1).uppercased())\(key.dropFirst()):")) {
                config.preferences.setValue(false, forKey: key)
            }
        }
        config.userContentController.addUserScript(WKUserScript(source: mediaScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let disguise = site.disguise {
            config.userContentController.addUserScript(WKUserScript(source: disguise, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        config.userContentController.addUserScript(WKUserScript(source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(self, name: "pocketNotify")
        if let watch = site.watch {
            config.userContentController.addUserScript(WKUserScript(source: watch, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            config.userContentController.add(self, name: "pocketWatch")
        }
        let web = WKWebView(frame: container.bounds, configuration: config)
        prepare(web)
        web.autoresizingMask = [.width, .height]
        web.customUserAgent = site.agent
        web.allowsBackForwardNavigationGestures = false
        web.pageZoom = site.zoom
        if #available(macOS 13.3, *) { web.isInspectable = true }
        if site.realtime, web.responds(to: NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")) {
            web.setValue(false, forKey: "windowOcclusionDetectionEnabled")
        }
        web.navigationDelegate = self
        web.uiDelegate = self
        titleWatch = web.observe(\.title, options: [.new]) { [weak self] view, _ in
            self?.unread = WebApp.unreadCount(view.title ?? "")
        }
        container.addSubview(web)
        self.web = web
        web.load(URLRequest(url: site.url))
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.checkHealth() }
        healthTimer?.tolerance = 60
        note("pocket loading app=\(spec.id) reason=\(reason) realtime=\(site.realtime) url=\(site.url.absoluteString)")
    }

    func prepare(_ web: WKWebView) {}

    func unload(reason: String) {
        guard let web else { return }
        healthTimer?.invalidate()
        healthTimer = nil
        titleWatch = nil
        popups.values.forEach { closePopup($0.view, reason: reason) }
        web.configuration.userContentController.removeScriptMessageHandler(forName: "pocketNotify")
        if site.watch != nil { web.configuration.userContentController.removeScriptMessageHandler(forName: "pocketWatch") }
        web.stopLoading()
        web.removeFromSuperview()
        self.web = nil
        unread = 0
        note("pocket unloaded app=\(spec.id) reason=\(reason)")
    }

    override func stop() {
        unloadWork?.cancel()
        unload(reason: "app disabled")
        super.stop()
        note("pocket stopped app=\(spec.id)")
    }

    func checkHealth() {
        guard let web else { return }
        var answered = false
        web.evaluateJavaScript("document.visibilityState") { [weak self] _, error in
            guard let self else { return }
            answered = true
            guard let error else { return }
            note("pocket health failed app=\(self.spec.id) cause=\(error.localizedDescription); reloading")
            self.web?.load(URLRequest(url: self.site.url))
        }
        checkPlayer(reason: "health")
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, !answered, self.web != nil else { return }
            self.restart(reason: "health timed out")
        }
    }

    func checkPlayer(reason: String) {
        guard site.watch != nil, let web else { return }
        web.evaluateJavaScript(connectedProbe) { [weak self] connected, _ in
            guard let self, connected as? Bool == false else { return }
            self.web?.evaluateJavaScript(playingProbe) { [weak self] playing, _ in
                guard let self, let web = self.web else { return }
                let busy = playing as? Bool == true
                note("pocket player disconnected app=\(self.spec.id) reason=\(reason) playing=\(busy) action=\(busy ? "kept" : "reload")")
                if !busy { web.load(URLRequest(url: self.site.url)) }
            }
        }
    }

    static let unreadPattern = try! Regex(#"\(([\d,]+)\)"#)

    static func unreadCount(_ title: String) -> Int {
        if let match = title.firstMatch(of: unreadPattern), let digits = match.output[1].substring,
           let count = Int(digits.replacingOccurrences(of: ",", with: "")) { return count }
        if title.hasPrefix("*") || title.hasPrefix("!") { return -1 }
        return 0
    }

    var inCall: Bool {
        guard let web else { return false }
        return ([web] + popups.values.map(\.view)).contains { $0.microphoneCaptureState != .none || $0.cameraCaptureState != .none }
    }

    override func shouldStayOpen() -> Bool {
        if choosingFile || inCall || !popups.isEmpty { return true }
        if let key = NSApp.keyWindow, popups.values.contains(where: { $0.window === key }) { return true }
        return false
    }

    override func didShow() {
        unloadWork?.cancel()
        load(reason: "opened")
        checkPlayer(reason: "opened")
        panel.makeFirstResponder(web)
    }

    override func didHide() { scheduleUnload() }

    func scheduleUnload() {
        guard let limit = site.unloadAfter else { return }
        unloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let web = self.web, !self.isShown else { return }
            if self.inCall { return self.scheduleUnload() }
            web.evaluateJavaScript(playingProbe) { [weak self] result, _ in
                guard let self else { return }
                if result as? Bool == true { return self.scheduleUnload() }
                self.unload(reason: "idle \(Int(limit))s")
            }
        }
        unloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: work)
    }

    override func menuItems() -> [NSMenuItem] {
        [NSMenuItem(title: "Reload \(spec.name)", action: #selector(reload), keyEquivalent: ""),
         NSMenuItem(title: "Restart \(spec.name) (if frozen)", action: #selector(restartFromMenu), keyEquivalent: ""),
         NSMenuItem(title: "Open \(spec.name) in browser", action: #selector(openOutside), keyEquivalent: "")]
            .map { $0.target = self; return $0 }
    }

    @objc func reload() {
        note("pocket reload app=\(spec.id) source=menu loaded=\(web != nil)")
        web?.load(URLRequest(url: site.url))
    }

    @objc func restartFromMenu() { restart(reason: "menu") }

    func restart(reason: String) {
        guard let web else { return }
        let pid = web.responds(to: NSSelectorFromString("_webProcessIdentifier")) ? (web.value(forKey: "_webProcessIdentifier") as? Int ?? 0) : 0
        guard pid > 0 else {
            note("pocket restart fell back to reload app=\(spec.id) reason=\(reason) cause=no web process id")
            web.load(URLRequest(url: site.url))
            return
        }
        let result = kill(pid_t(pid), SIGKILL)
        note("pocket restart app=\(spec.id) reason=\(reason) pid=\(pid) killed=\(result == 0) errno=\(result == 0 ? 0 : errno)")
        if result != 0 { web.load(URLRequest(url: site.url)) }
    }

    @objc func openOutside() { NSWorkspace.shared.open(site.url) }

    func ownsHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return site.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func staysInside(_ host: String?) -> Bool {
        guard let host else { return false }
        return ownsHost(host) || signInHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { return decisionHandler(.download) }
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame ?? true, let url = action.request.url,
           !staysInside(url.host) {
            note("pocket link opened outside app=\(spec.id) host=\(url.host ?? "-")")
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var target = folder.appendingPathComponent(suggestedFilename)
        var n = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        note("pocket download started app=\(spec.id) file=\(target.lastPathComponent)")
        completionHandler(target)
    }

    func downloadDidFinish(_ download: WKDownload) {
        note("pocket download finished app=\(spec.id)")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        note("pocket download failed app=\(spec.id) cause=\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = action.request.url
        let host = url?.host
        let blank = url == nil || url?.absoluteString.isEmpty == true || url?.scheme == "about" || url?.scheme == "blob"
        if blank || ownsHost(host) {
            return openPopup(configuration: configuration, request: action.request, features: windowFeatures)
        }
        if staysInside(host) {
            note("pocket new window kept inside app=\(spec.id) host=\(host ?? "-")")
            webView.load(action.request)
            return nil
        }
        if let url, url.scheme?.hasPrefix("http") == true {
            note("pocket new window opened outside app=\(spec.id) host=\(host ?? "-")")
            NSWorkspace.shared.open(url)
        } else {
            note("pocket new window dropped app=\(spec.id) scheme=\(url?.scheme ?? "-")")
        }
        return nil
    }

    func openPopup(configuration: WKWebViewConfiguration, request: URLRequest, features: WKWindowFeatures) -> WKWebView {
        let width = CGFloat(truncating: features.width ?? 420)
        let height = CGFloat(truncating: features.height ?? 320)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
        view.customUserAgent = site.agent
        view.uiDelegate = self
        view.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "\(spec.name) call"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        window.delegate = self
        if let area = (panel.screen ?? NSScreen.main)?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: panel.frame.minX - width - 12 > area.minX ? panel.frame.minX - width - 12 : area.maxX - width - 12,
                                          y: area.maxY - height - 40))
        }
        popups[ObjectIdentifier(view)] = (view, window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        note("pocket popup opened app=\(spec.id) host=\(request.url?.host ?? "blank") size=\(Int(width))x\(Int(height)) open=\(popups.count)")
        return view
    }

    func closePopup(_ view: WKWebView, reason: String) {
        guard let entry = popups.removeValue(forKey: ObjectIdentifier(view)) else { return }
        entry.window.delegate = nil
        entry.window.orderOut(nil)
        entry.view.stopLoading()
        note("pocket popup closed app=\(spec.id) reason=\(reason) host=\(view.url?.host ?? "-") open=\(popups.count)")
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopup(webView, reason: "page closed")
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window !== panelIfLoaded,
              let entry = popups.values.first(where: { $0.window === window }) else { return }
        entry.view.evaluateJavaScript("window.close()")
        closePopup(entry.view, reason: "window closed")
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let chooser = NSOpenPanel()
        chooser.allowsMultipleSelection = parameters.allowsMultipleSelection
        chooser.canChooseDirectories = parameters.allowsDirectories
        choosingFile = true
        NSApp.activate(ignoringOtherApps: true)
        chooser.begin { [weak self] result in
            guard let self else { return }
            self.choosingFile = false
            note("pocket file chooser closed app=\(self.spec.id) picked=\(result == .OK ? chooser.urls.count : 0)")
            completionHandler(result == .OK ? chooser.urls : nil)
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowed = ownsHost(origin.host)
        note("pocket media permission app=\(spec.id) host=\(origin.host) type=\(type.rawValue) granted=\(allowed)")
        decisionHandler(allowed ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = spec.name
        alert.informativeText = message
        alert.beginSheetModal(for: webView.window ?? panel) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = spec.name
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: webView.window ?? panel) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        note("pocket loaded app=\(spec.id) host=\(webView.url?.host ?? "-")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView !== web { return note("pocket popup load failed app=\(spec.id) code=\((error as NSError).code)") }
        retry(after: error, stage: "load")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView !== web { return note("pocket popup connect failed app=\(spec.id) code=\((error as NSError).code)") }
        retry(after: error, stage: "connect")
    }

    func retry(after error: Error, stage: String) {
        let code = (error as NSError).code
        if code == NSURLErrorCancelled || code == 102 { return }
        note("pocket load failed app=\(spec.id) stage=\(stage) code=\(code) cause=\(error.localizedDescription); retrying in 15s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, let web = self.web, web.url == nil || web.isLoading == false else { return }
            web.load(URLRequest(url: self.site.url))
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView !== web { return closePopup(webView, reason: "process ended") }
        note("pocket web process ended app=\(spec.id); reloading")
        webView.load(URLRequest(url: site.url))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String] else { return }
        if message.name == "pocketWatch" {
            return note("pocket web watch app=\(spec.id) kind=\(body["kind"] ?? "-") shown=\(isShown) detail=\(body["detail"] ?? "-")")
        }
        if isShown && panel.isKeyWindow { return }
        let content = UNMutableNotificationContent()
        content.title = body["title"]?.isEmpty == false ? body["title"]! : spec.name
        content.body = body["body"] ?? ""
        content.sound = .default
        content.userInfo = ["app": spec.id]
        let id = "\(spec.id)-\(body["tag"]?.isEmpty == false ? body["tag"]! : UUID().uuidString)"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { [id = spec.id] error in
            if let error { note("pocket notification failed app=\(id) cause=\(error.localizedDescription)") }
        }
        note("pocket notification posted app=\(spec.id) bodyChars=\(content.body.count)")
    }
}
