import AppKit

/// The primary window's standing while first-run setup owns the screen.
///
/// SwiftUI builds and orders in the `browser` window before the wizard exists,
/// so a first run would otherwise leave an empty Crest window in front of setup.
/// Zero alpha hides that window from the eye but not from accessibility: it
/// stays a real, addressable, occasionally *main* window titled "Crest", so
/// VoiceOver and automation both find a phantom standing over the wizard.
/// Answering `false` from the window's own accessibility element is not a way
/// out — AppKit later throws out of `NSApp.accessibilityWindows` when a window
/// answers that way — so the gate orders the window off screen for as long as
/// setup runs and orders it back when setup hands the screen to the browser.
@MainActor
enum BrowserOnboardingLaunchGateWindow {
    private static weak var retiredWindow: NSWindow?
    private static var retirementTask: Task<Void, Never>?

    static func retire(_ window: NSWindow) {
        // Zero alpha still matters: it keeps the window from painting a blank
        // frame in the moment between AppKit ordering it in and the gate
        // ordering it out.
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        retiredWindow = window
        guard retirementTask == nil else { return }
        // `viewDidMoveToWindow` runs before AppKit has ordered the window in, so
        // a single `orderOut` there would land on a window that is not yet on
        // screen and do nothing at all. The gate therefore keeps watch for as
        // long as it owns the launch, which also answers a Dock click reopening
        // the window while the wizard is still running.
        retirementTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let window = retiredWindow else { return }
                if window.isVisible {
                    window.orderOut(nil)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    static func restore() {
        retirementTask?.cancel()
        retirementTask = nil
        guard let window = retiredWindow else { return }
        retiredWindow = nil
        window.alphaValue = 1
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
    }
}
