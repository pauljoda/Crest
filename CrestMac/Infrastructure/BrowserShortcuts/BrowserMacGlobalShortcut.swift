import AppKit
import Carbon.HIToolbox

/// The keys bound to one command, registered with the system so they reach
/// Crest while another app is in front. The registration follows the binding
/// as it changes, and the keyboard layout as it switches, for as long as
/// Crest runs; a binding no key on the layout types registers nothing. While
/// Crest is in front the keys stay unregistered, so they reach its menus,
/// pages and shortcut recorder as any other keys do.
@MainActor
final class BrowserMacGlobalShortcut {
    // MARK: - Static Variables

    /// The signature Crest's hot keys carry, its four-character code.
    private static let signature: OSType = 0x4352_5354

    // MARK: - Variables

    private let binding: @MainActor () -> BrowserShortcut?
    private let pressed: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var observers: [any NSObjectProtocol] = []

    // MARK: - Initializers

    /// A shortcut on the keys `binding` answers, which runs `pressed`.
    init(binding: @escaping @MainActor () -> BrowserShortcut?, pressed: @escaping @MainActor () -> Void) {
        self.binding = binding
        self.pressed = pressed
    }

    // MARK: - Actions - Registration

    /// Registers the binding's keys and keeps them registered as they change.
    func start() {
        guard handler == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<BrowserMacGlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { shortcut.pressed() }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let reregister: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
        observers = [
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
                queue: .main, using: reregister),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: reregister),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: reregister),
        ]
        follow()
    }

    private func follow() {
        withObservationTracking {
            register()
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    private func register() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        // Shift alone would take an ordinary typed character from every app.
        guard let shortcut = binding(), !NSApp.isActive,
            !shortcut.modifiers.isDisjoint(with: [.command, .control, .option]),
            let keyCode = shortcut.key.virtualKeyCode(shifted: shortcut.modifiers.contains(.shift))
        else { return }
        let status = RegisterEventHotKey(
            UInt32(keyCode), shortcut.modifiers.carbonModifiers, EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), 0, &hotKey)
        // If registration fails, the shortcut still works inside Crest.
        if status != noErr { DiagnosticLog.shortcuts.notice("Could not register a global shortcut: \(status)") }
    }
}

extension BrowserShortcutKey {
    /// The key that types this one on the current keyboard layout, as Crest's
    /// own shortcuts match it, or on the current Latin layout for a key the
    /// current one does not type, or nil when neither does. A shortcut with Shift records the
    /// character Shift types, such as `?`, so `shifted` looks for that one.
    fileprivate func virtualKeyCode(shifted: Bool) -> UInt16? {
        switch self {
        case .special(let special):
            BrowserShortcutHardwareKeyCode.allCases.first { ShortcutSpecialKey(keyCode: $0.rawValue) == special }?
                .rawValue
        case .character(let character):
            Self.virtualKeyCode(typing: character, shifted: shifted)
        }
    }

    private static func virtualKeyCode(typing character: Character, shifted: Bool) -> UInt16? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource(),
        ]
        .compactMap { $0?.takeRetainedValue() }
        return sources.lazy.compactMap { virtualKeyCode(typing: character, shifted: shifted, on: $0) }.first
    }

    private static func virtualKeyCode(typing character: Character, shifted: Bool, on source: TISInputSource)
        -> UInt16?
    {
        // UCKeyTranslate takes the Carbon modifier bits shifted down a byte.
        let modifierState = shifted ? UInt32(shiftKey >> 8) : 0
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let target = String(character).lowercased()
        return layoutData.withUnsafeBytes { bytes -> UInt16? in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            for keyCode in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
                    OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length,
                    &characters)
                if status == noErr, String(utf16CodeUnits: characters, count: length).lowercased() == target {
                    return keyCode
                }
            }
            return nil
        }
    }
}
