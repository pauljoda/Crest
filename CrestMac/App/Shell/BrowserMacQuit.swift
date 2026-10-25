import AppKit
import SwiftUI

/// Holds a quit until the core agrees to it and the edits the app accepted
/// are saved and staged for sync, then lets the entry point that asked finish
/// it: the engine that owns the process quits itself, and AppKit replies to
/// its own termination request. Nothing else ends the process before the
/// core's storage worker wrote the newest revision or its stager staged it.
@MainActor
final class BrowserMacQuit {
    // MARK: - Static Variables

    static let suppressionKey = "suppressQuitConfirmation"

    // MARK: - Variables

    private unowned let application: BrowserMacApplication
    private unowned let windows: BrowserMacWindows
    /// A quit is being prepared or finished, so nothing new opens.
    private(set) var isQuitting = false
    /// The quit was allowed and handed to its entry point to finish.
    private var hasFinished = false
    private var confirmationPanel: NSPanel?

    // MARK: - Initializers

    init(application: BrowserMacApplication, windows: BrowserMacWindows) {
        self.application = application
        self.windows = windows
    }

    // MARK: - Actions - Quitting

    /// Confirms an explicit menu or keyboard quit before starting the normal
    /// page, download and persistence checks. System termination bypasses this.
    func confirmUserRequest() {
        guard !isQuitting, confirmationPanel == nil else { return }
        // Suppressing a native confirmation is local to this app installation.
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.suppressionKey) else {
            NSApp.terminate(nil)
            return
        }
        let content = BrowserQuitConfirmation(
            icon: NSApp.applicationIconImage,
            cancel: { [weak self] in self?.finishUserConfirmation(quit: false) },
            quit: { [weak self] in self?.finishUserConfirmation(quit: true) },
            quitWithoutAskingAgain: { [weak self] in
                self?.finishUserConfirmation(quit: true, suppress: true)
            })
        let host = NSHostingView(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = String(localized: "Quit Crest?")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        confirmationPanel = panel
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.beginSheet(panel)
        } else {
            panel.center()
            NSApp.runModal(for: panel)
        }
    }

    private func finishUserConfirmation(quit: Bool, suppress: Bool = false) {
        guard let panel = confirmationPanel else { return }
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else if NSApp.modalWindow === panel {
            NSApp.stopModal()
        }
        panel.orderOut(nil)
        confirmationPanel = nil
        if suppress { UserDefaults.standard.set(true, forKey: Self.suppressionKey) }
        if quit { NSApp.terminate(nil) }
    }

    /// Asks to quit, which `finish` completes with whether it may: on a later
    /// turn of the main actor, once the core asked every page and the person
    /// about downloads in progress. Once allowed, the core keeps the windows
    /// open now for the next launch, the Quick Windows close and every edit is
    /// flushed before `finish` runs. Answers false when the shell has nothing
    /// to hold, having finished already, so the entry point quits at once.
    ///
    /// A quit the core defers while a Space is deleted is asked for again once
    /// the deletion moves on, through the application's own `terminate`, which
    /// reaches this again from the entry point.
    func request(finish: @escaping @MainActor (_ allowed: Bool) -> Void) -> Bool {
        guard !hasFinished else { return false }
        guard !isQuitting else { return true }
        isQuitting = true
        application.quitPreparation.prepare(
            retry: { NSApp.terminate(nil) },
            completion: { [weak self] allowed in
                guard let self else { return }
                guard allowed else {
                    isQuitting = false
                    // An update relaunch that asked for this quit is offered again.
                    application.softwareUpdates.model.applicationStayedOpen()
                    finish(false)
                    return
                }
                // The core keeps the windows open now for the next launch
                // before any of them closes as the app goes.
                application.rememberWindowsForLaunch()
                Task { @MainActor in
                    self.windows.closeQuickWindowsWithoutAsking()
                    await self.application.flushPendingPersistenceBeforeQuit()
                    self.hasFinished = true
                    finish(true)
                }
            })
        return true
    }
}
