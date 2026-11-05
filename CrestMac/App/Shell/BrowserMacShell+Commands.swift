import AppKit

extension BrowserMacShell {
    // MARK: - Variables

    /// The menu bar's commands as they run in the key browser window.
    var activeActions: BrowserCommandActions? {
        windows?.activeActions
    }

    /// The commands as they run on the page in front: a key Quick Window's
    /// own page, or else the key browser window's.
    var pageActions: BrowserCommandActions? {
        windows?.activeQuickWindowActions ?? activeActions
    }

    /// Whether the application can check for updates, which an isolated
    /// launch without an update feed cannot.
    var canCheckForUpdates: Bool {
        application?.softwareUpdates.isEnabled == true
    }

    // MARK: - Actions - Shortcuts

    /// Runs the Crest command `event`'s chord is bound to, or an engine
    /// binding no Crest command claims, such as an extension's, and answers
    /// whether it was taken. The shell is offered every key down before any
    /// view sees it, when an engine is about to hand one to a page, and when
    /// the menu bar's items let one go; `stage` says which.
    ///
    /// Before a page, the command's preference decides, as in other browsers:
    /// Prefer Crest runs it now; Use Both runs it on a quick second press of
    /// keys the page kept; otherwise the page's engine hands a key the page
    /// lets go to the menu bar, which runs the command then. Crest's own
    /// views, such as the location field or the sidebar, get every Crest
    /// shortcut before they see the key. Text editing keys bound to a command
    /// always reach the focused page or field first, and the menu bar runs the
    /// command when the field has nothing to do with them.
    func handleShortcut(_ event: NSEvent, at stage: BrowserMacKeyStage) -> Bool {
        // While a Most Recent Tab shortcut is held, its keys are the
        // switcher's and no page or command sees them.
        if event.type == .keyDown, recentTabSwitcher.handleKeyDown(event) { return true }
        guard let windows, let application, event.type == .keyDown,
            NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil,
            (NSApp.keyWindow?.firstResponder as? ShortcutRecorderButton)?.isRecording != true,
            let shortcut = BrowserShortcut(event: event), shortcut.isValid
        else { return false }
        if shortcut == BrowserShortcut(key: .character("q"), modifiers: .command) {
            NSApp.terminate(nil)
            return true
        }
        guard !isQuitting else { return true }
        // A focused Chromium page keeps the window-cycling key from AppKit,
        // so it cycles here for every page.
        if BrowserMacWindowCycling.cycle(for: event) { return true }
        // The application menu runs Settings once a page lets the key go.
        if !stage.pageSeesFirst, shortcut == BrowserShortcut(key: .character(","), modifiers: .command) {
            BrowserMacApplicationAction.settings.perform(in: self)
            return true
        }
        // Inspector, extension popup and system dialog responders are not a
        // browser workspace. Their editing and close shortcuts stay local.
        let context = windows.activeContext
        guard context != nil || windows.isQuickWindowKey else { return false }
        if let command = application.shortcuts.command(for: event, isEnabled: canPerform) {
            if stage.viewSeesFirst, application.shortcuts.yieldsToTextEditing(command) { return false }
            if stage.pageSeesFirst, !runsBeforePage(command, pressed: event, shortcut: shortcut) { return false }
            if let direction = BrowserMacCommand.of(command)?.recentTabDirection,
                recentTabSwitcher.begin(direction: direction)
            {
                return true
            }
            perform(command)
            return true
        }
        // What no Crest command claims can belong to the engine, such as an
        // extension's binding in the Space of the page in front: a key Quick
        // Window's page, a Peek, or the active tab. It goes ahead of the page
        // as it does in Chrome.
        guard let page = pageActions?.commandPage else { return false }
        return engineHost.handleUnclaimedShortcut(event, page: page)
    }

    /// Whether `command` runs before the focused page sees `event`, a press of
    /// `shortcut`: its preference is Prefer Crest, or it is Use Both and this
    /// presses again keys the page kept. Any other Use Both press is one the
    /// page sees first, unless an input method is composing text there.
    private func runsBeforePage(_ command: ShortcutCommand, pressed event: NSEvent, shortcut: BrowserShortcut) -> Bool {
        guard let preference = application?.shortcuts.preference(for: command) else { return false }
        if preference.runsBeforePage { return true }
        guard preference.takesSecondPress,
            (NSApp.keyWindow?.firstResponder as? NSTextInputClient)?.hasMarkedText() != true
        else { return false }
        if pageKeptShortcut.isSecondPress(event, of: command, shortcut: shortcut) { return true }
        pageKeptShortcut.pageSees(event, of: command, shortcut: shortcut)
        return false
    }

    /// Takes `event` at the menu bar before any item matches it, and answers
    /// whether it was taken. A press a page let go is no longer one it kept,
    /// and one whose second press already ran its command is dropped. Text
    /// editing keys bound to a command go to the Edit menu's item while the
    /// focused page or field takes text and the item can act, and to the
    /// command otherwise, wherever its menu sits.
    func menuBarReceives(_ event: NSEvent, editMenu: NSMenu?) -> Bool {
        if pageKeptShortcut.pageLetGo(event) { return true }
        guard let application, event.type == .keyDown, let shortcut = BrowserShortcut(event: event),
            let command = application.shortcuts.command(for: shortcut, isEnabled: canPerform),
            application.shortcuts.yieldsToTextEditing(command)
        else { return false }
        if (NSApp.keyWindow?.firstResponder as? NSView)?.inputContext != nil, let editMenu,
            let item = editMenu.items.first(where: { BrowserShortcut(keyEquivalentOf: $0) == shortcut })
        {
            editMenu.update()
            if item.isEnabled, let action = item.action, NSApp.sendAction(action, to: item.target, from: item) {
                return true
            }
        }
        perform(command)
        return true
    }

    // MARK: - Actions - Commands

    /// Whether `command` can run now: never while a quit is prepared or a
    /// modal window or sheet is up, and otherwise as the key window's own
    /// commands say. A new window needs no window, and any window the shell
    /// opened, such as a Quick Window or setup, can close itself.
    func canPerform(_ command: ShortcutCommand) -> Bool {
        guard !isQuitting, NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil else { return false }
        if let windowless = BrowserMacCommand.of(command)?.withoutWindow, let windows {
            return actions(for: command) != nil || windowless.isAvailable(windows)
        }
        return actions(for: command)?.canPerform(command) == true
    }

    /// Runs `command` in the key browser window, or on the page of a key
    /// Quick Window, or with neither, the commands that need no window.
    func perform(_ command: ShortcutCommand) {
        guard canPerform(command) else { return }
        if let actions = actions(for: command) {
            actions.perform(command)
            return
        }
        if let windows { BrowserMacCommand.of(command)?.withoutWindow?.run(windows) }
    }

    /// The actions `command` runs with now: the page in front's for a command
    /// on a page, or else the key browser window's.
    func actions(for command: ShortcutCommand) -> BrowserCommandActions? {
        BrowserMacCommand.of(command)?.actsOnPage == true ? pageActions : activeActions
    }

    // MARK: - Actions - Engine window requests

    /// Focuses the key window's location field.
    func focusLocation() {
        activeActions?.openLocation()
    }

    /// Crest keeps a page by pinning its tab.
    func bookmarkActivePage() {
        activeActions?.toggleSelectedTabPinned()
    }

    /// Shows the key window's launcher, which searches its tabs.
    func showTabSearch() {
        windows?.activeContext?.chrome.presentCommandPalette()
    }

    // MARK: - Actions - Application

    /// The standard About panel, crediting the engine that owns the process.
    func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: ProductIdentity.name,
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "",
            .applicationIcon: NSApp.applicationIconImage as Any,
        ]
        if let credits = engineHost.aboutCredits { options[.credits] = NSAttributedString(string: credits) }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    func checkForUpdates() {
        application?.softwareUpdates.checkForUpdates()
    }

    /// Opens Settings in the browser window the person is using, opening one
    /// only when none is open.
    func openSettings() {
        guard let context = windows?.contextBringingBrowserWindowForward() else { return }
        application?.openSettings(in: context.windowID)
    }

    /// Whether any agent is connected now.
    var hasConnectedAgents: Bool {
        application?.browser.core.state.agentSessions.isEmpty == false
    }

    /// Stops every agent at once.
    func stopAllAgents() {
        _ = try? application?.browser.core.send(StopAllAgents())
    }

    /// Opens Getting Started in the browser window the person is using,
    /// opening one only when none is open.
    func openGettingStarted() {
        guard let context = windows?.contextBringingBrowserWindowForward() else { return }
        application?.openGettingStarted(in: context.windowID)
    }
}
