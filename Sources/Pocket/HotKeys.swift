import Carbon
import Foundation

final class HotKeys {
    var refs: [EventHotKeyRef] = []
    var ids: [String] = []
    var installed = false

    static let letters: [UInt32: String] = [
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_K): "K",
    ]

    func install() {
        guard !installed else { return }
        installed = true
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            DispatchQueue.main.async {
                let keys = AppDelegate.shared.hotKeys.ids
                guard keys.indices.contains(index) else { return }
                AppDelegate.shared.open(keys[index], source: "hotkey")
            }
            return noErr
        }, 1, &event, nil, nil)
        if status != noErr { note("pocket hotkey handler install failed status=\(status)") }
    }

    func register(_ specs: [AppSpec]) {
        let wanted = specs.filter { $0.hotKey != nil }.map(\.id)
        guard wanted != ids || refs.isEmpty != wanted.isEmpty else { return }
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        ids = []
        install()
        for spec in specs {
            guard let key = spec.hotKey else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(optionKey), EventHotKeyID(signature: OSType(0x504B4554), id: UInt32(ids.count)),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                ids.append(spec.id)
            } else {
                note("pocket hotkey failed app=\(spec.id) key=option+\(HotKeys.letters[key] ?? "\(key)") status=\(status)")
            }
        }
        note("pocket hotkeys registered apps=\(ids.joined(separator: ","))")
    }
}
