import Carbon
import Foundation

struct WebSpec {
    let url: URL
    let store: UUID
    let hosts: [String]
    let zoom: Double
    let agent: String
    let disguise: String?
    let realtime: Bool
    let unloadAfter: TimeInterval?
}

struct AppSpec {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    let glyph: String?
    let hotKey: UInt32?
    let web: WebSpec?
}

let safariAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

let chromeAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"

let chromeDisguise = """
(() => {
  const brands = [{ brand: "Google Chrome", version: "146" }, { brand: "Chromium", version: "146" }, { brand: "Not.A/Brand", version: "99" }];
  const data = {
    brands, mobile: false, platform: "macOS",
    getHighEntropyValues: () => Promise.resolve({ brands, mobile: false, platform: "macOS", platformVersion: "15.0.0", architecture: "arm", bitness: "64", fullVersionList: brands, uaFullVersion: "146.0.0.0" }),
    toJSON: () => ({ brands, mobile: false, platform: "macOS" }),
  };
  Object.defineProperty(Navigator.prototype, "userAgentData", { get: () => data, configurable: true });
  Object.defineProperty(Navigator.prototype, "vendor", { get: () => "Google Inc.", configurable: true });
  if (!window.chrome) window.chrome = { runtime: {} };
})();
"""

let signInHosts = ["facebook.com", "accounts.google.com", "accounts.youtube.com", "appleid.apple.com", "login.microsoftonline.com", "login.live.com",
                   "okta.com", "oktapreview.com", "jumpcloud.com", "onelogin.com", "auth0.com"]

let catalog: [AppSpec] = [
    AppSpec(id: "whatsapp", name: "WhatsApp", summary: "WhatsApp Web, kept connected for messages and calls", symbol: "message.fill",
            glyph: Glyphs.whatsapp, hotKey: UInt32(kVK_ANSI_W),
            web: WebSpec(url: URL(string: "https://web.whatsapp.com/")!, store: UUID(uuidString: "6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A01")!,
                         hosts: ["whatsapp.com", "whatsapp.net"], zoom: 0.8, agent: safariAgent, disguise: nil, realtime: true, unloadAfter: nil)),
    AppSpec(id: "slack", name: "Slack", summary: "Slack in a panel, with notifications and huddles", symbol: "number",
            glyph: Glyphs.slack, hotKey: UInt32(kVK_ANSI_S),
            web: WebSpec(url: URL(string: "https://app.slack.com/client")!, store: UUID(uuidString: "6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A02")!,
                         hosts: ["slack.com", "slack-edge.com", "slack-imgs.com", "slackb.com"], zoom: 0.85, agent: chromeAgent, disguise: chromeDisguise, realtime: true, unloadAfter: nil)),
    AppSpec(id: "spotify", name: "Spotify", summary: "Spotify web player that keeps playing when hidden", symbol: "music.note",
            glyph: Glyphs.spotify, hotKey: UInt32(kVK_ANSI_M),
            web: WebSpec(url: URL(string: "https://open.spotify.com/")!, store: UUID(uuidString: "6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A03")!,
                         hosts: ["spotify.com", "scdn.co", "spotifycdn.com", "spotify.net", "spotify.link"], zoom: 0.85, agent: safariAgent, disguise: nil, realtime: false, unloadAfter: 1800)),
    AppSpec(id: "gmail", name: "Gmail", summary: "Gmail with unread count and new-mail notifications", symbol: "envelope.fill",
            glyph: Glyphs.gmail, hotKey: UInt32(kVK_ANSI_G),
            web: WebSpec(url: URL(string: "https://mail.google.com/mail/")!, store: UUID(uuidString: "6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A04")!,
                         hosts: ["mail.google.com", "google.com", "gstatic.com", "googleusercontent.com", "googleapis.com"], zoom: 0.85, agent: safariAgent, disguise: nil, realtime: false, unloadAfter: nil)),
    AppSpec(id: "outlook", name: "Outlook", summary: "Outlook mail for work or personal Microsoft accounts", symbol: "tray.full.fill",
            glyph: nil, hotKey: UInt32(kVK_ANSI_O),
            web: WebSpec(url: URL(string: "https://outlook.office.com/mail/")!, store: UUID(uuidString: "6B1F2C1E-0A57-4C3B-9E4B-0E5C4A0F7A05")!,
                         hosts: ["outlook.office.com", "outlook.office365.com", "outlook.live.com", "office.com", "office365.com", "office.net", "live.com", "outlook.com", "microsoft.com", "microsoftonline.com", "msauth.net", "msftauth.net", "live.net"],
                         zoom: 0.85, agent: safariAgent, disguise: nil, realtime: false, unloadAfter: nil)),
    AppSpec(id: "calendar", name: "Calendar", summary: "Month view of the events in your Mac's Calendar app", symbol: "calendar",
            glyph: nil, hotKey: UInt32(kVK_ANSI_C), web: nil),
]

func spec(_ id: String) -> AppSpec? { catalog.first { $0.id == id } }
