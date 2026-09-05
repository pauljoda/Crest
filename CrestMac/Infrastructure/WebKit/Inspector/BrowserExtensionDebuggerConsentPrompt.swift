import AppKit

/// The user's decision before an extension is handed control of a Space's pages.
///
/// The extension permission delegate builds its own `NSAlert` inline and its
/// helper is private, single-purpose, and phrased for WebKit's permission
/// identifiers ("This extension is requesting permissions: tabs"). None of that
/// describes what a debugger attachment actually does, and the copy could not
/// be supplied from outside, so this is a second, deliberately narrow prompt
/// rather than a widened first one.
@MainActor
enum BrowserExtensionDebuggerConsentPrompt {
    /// Presents the prompt and reports whether the user allowed it.
    ///
    /// The answer is durable per Space: Chrome asks once at install time for a
    /// permission Crest instead asks for at first use, so a prompt on every
    /// attach would be worse than either.
    static func present(extensionName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = String(
                localized: "Allow \(extensionName) to control this Space?",
                comment: """
                    Title of the prompt asking to grant an extension debugger \
                    access. The placeholder is the extension's name.
                    """
            )
            alert.informativeText = String(
                localized: """
                    This extension wants to read and control the pages in this Space. It will be able to see \
                    everything on those pages, including what you type, and act as you on them.

                    You can stop it at any time from the banner above a controlled page, or change this in \
                    the Space's extension settings.
                    """,
                comment: "Body of the prompt asking to grant an extension debugger access."
            )
            alert.addButton(withTitle: String(localized: "Allow"))
            alert.addButton(withTitle: String(localized: "Don’t Allow"))
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            } else {
                continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
            }
        }
    }
}
