import AppKit
import Carbon.HIToolbox

/// Global ⌥⌘P shortcut that toggles the overlay from anywhere.
/// Uses Carbon's RegisterEventHotKey, which needs no accessibility
/// permissions (unlike CGEventTap-based approaches).
enum HotKey {
    private static var hotKeyRef: EventHotKeyRef?
    /// False when RegisterEventHotKey fails, so the menu never advertises a
    /// shortcut that was not registered. Carbon does not report a clash with
    /// another app's identical shortcut, so success is not a guarantee.
    private(set) static var isRegistered = false

    static func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C callback: no captures allowed, so it reaches for the singleton.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                let state = AppState.shared
                if state.shouldShowOverlay {
                    state.isEnabled = false
                } else {
                    state.cancelSnooze()
                    state.isEnabled = true
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: 0x4443_4B4C /* 'DCKL' */, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = status == noErr
        if !isRegistered {
            NSLog("[Deckle] ⌥⌘P unavailable (RegisterEventHotKey status \(status))")
        }
    }
}
