import AppKit

@MainActor
enum BrowserOnboardingWindowActivation {
    /// The window name assistive technology uses to find the wizard. The
    /// wizard draws its own chrome, so nothing displays this — but the accessibility
    /// tree still needs a name to address the window by.
    static let windowTitle = "Crest Setup"

    static func bringForward() {
        Task { @MainActor in
            for attempt in 0..<8 {
                if attempt > 0 {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                NSApp.activate(ignoringOtherApps: true)
                guard let window = NSApp.windows.first(where: isSetupWindow) else {
                    continue
                }
                BrowserWindowAccessibility.pinTitle(windowTitle, on: window)
                window.hasShadow = false
                window.ignoresMouseEvents = false
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }

    static func isSetupWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == BrowserOnboardingCoordinator.sceneID
    }
}
