import AppKit

@MainActor
enum BrowserSettingsWindowSizing {
    static func apply(to window: NSWindow) {
        BrowserWindowAccessibility.pinTitle(
            BrowserSettingsChromePolicy.windowTitle,
            on: window
        )
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        if window.contentMinSize != BrowserSettingsChromePolicy.minimumContentSize {
            window.contentMinSize = BrowserSettingsChromePolicy.minimumContentSize
        }
        if window.contentMaxSize.width < 10_000
            || window.contentMaxSize.height < 10_000
        {
            window.contentMaxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        if window.standardWindowButton(.zoomButton)?.isEnabled == false {
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }
}
