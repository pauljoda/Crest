import AppKit

/// Owns the WebKit composition's launch and holds each quit until the edits
/// the app accepted are saved and staged for sync. SwiftUI runs no termination
/// hook that waits for queued work, so a quit would otherwise end the process
/// before the core's storage worker wrote the newest revision or its stager
/// staged it.
@MainActor
final class CrestAppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Variables

    let launch = BrowserApplicationLaunch {
        try BrowserMacApplication(pageClosePreparation: BrowserWebKitPageClosePreparer())
    }

    // MARK: - Actions - Termination

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let application = launch.value else { return .terminateNow }
        // Until the reply, AppKit runs the main run loop in its modal panel
        // mode, which still drains the main queue: the core's wake, the drain
        // that answers the flush and the end of each turn all run there.
        Task {
            await application.flushPendingPersistenceBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
