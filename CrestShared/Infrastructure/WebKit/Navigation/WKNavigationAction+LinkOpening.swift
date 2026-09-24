import WebKit

extension WKNavigationAction {
    /// Called only after WebKit has accepted a new-window request. It never
    /// supplies user activation or changes the popup permission decision.
    func selectsOpenedLink(using preferences: BrowserLinkPreferences) -> Bool {
        #if os(macOS)
            let option = modifierFlags.contains(.option)
            let middle = BrowserMouseButtonPolicy.isMiddleButton(number: buttonNumber)
        #else
            let option = modifierFlags.contains(.alternate)
            let middle = buttonNumber.rawValue == 1 << 2
        #endif
        var held: ShortcutModifiers = []
        if modifierFlags.contains(.command) { held.insert(.command) }
        if option { held.insert(.option) }
        return BrowserLinkOpeningPolicy.selectsNewTab(
            isNewTabGesture: preferences.peekClickModifier.opensNewTab(holding: held) || middle,
            isShiftModified: modifierFlags.contains(.shift),
            focusesNewTabs: preferences.focusesNewTabsOpenedFromLinks
        )
    }
}
