import Carbon
import Foundation

final class HotKeys {
    var refs: [EventHotKeyRef] = []
    var ids: [String] = []
    var installed = false
    var registered: [String]? = nil

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

    func register(_ wanted: [(id: String, keys: Shortcut)]) {
        let signature = wanted.map { "\($0.id)=\($0.keys.code):\($0.keys.mods)" }
        guard signature != registered else { return }
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        ids = []
        registered = signature
        install()
        for (id, keys) in wanted {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(keys.code, keys.mods, EventHotKeyID(signature: OSType(0x504B4554), id: UInt32(ids.count)),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                ids.append(id)
            } else {
                note("pocket hotkey failed app=\(id) keys=\(keys.display) status=\(status)")
            }
        }
        note("pocket hotkeys registered \(wanted.filter { ids.contains($0.id) }.map { "\($0.id)=\($0.keys.display)" }.joined(separator: ","))")
    }
}
