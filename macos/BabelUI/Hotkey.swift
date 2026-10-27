import Carbon.HIToolbox

/// A system-wide keyboard shortcut (Carbon hot key: works while another app is active and needs no
/// Accessibility / Input Monitoring permission). Registered for the life of the app.
final class Hotkey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private var ref: EventHotKeyRef?

    /// `keyCode` is a kVK_* value, `modifiers` Carbon flags (cmdKey, optionKey, controlKey, shiftKey).
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.installHandler()
        let id = UInt32(Self.handlers.count + 1)
        let hotKeyID = EventHotKeyID(signature: OSType(0x42554948), id: id)   // 'BUIH'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { Hotkey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
