import Carbon.HIToolbox

/// The system-wide ⌃⌥⌘K shortcut that turns sounds on or off from any app.
///
/// Uses the Carbon hot-key API, which needs no extra permission and only ever sees this
/// one key combination.
final class GlobalShortcut {
    static let display = "⌃⌥⌘K"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x4D43_4859), id: 1)  // "MCHY"
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        guard RegisterEventHotKey(UInt32(kVK_ANSI_K), modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
