#if CREST_CHROMIUM_HOST
import AppKit
import Observation
import SwiftUI

/// AppKit presentation of the existing Crest commands. Chromium keeps its page
/// context menus; browser menu actions always use the native Crest workspace.
@MainActor
final class CrestChromiumMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    enum ApplicationAction: String {
        case about, updates, settings, gettingStarted
    }
    private let shortcuts: BrowserShortcutStore
    private let actions: () -> BrowserCommandActions?
    private let perform: (BrowserShortcutCommand) -> Void
    private let canPerform: (BrowserShortcutCommand) -> Bool
    private let applicationAction: (ApplicationAction) -> Void
    private let canCheckForUpdates: () -> Bool
    private var commandItems: [(BrowserShortcutCommand, NSMenuItem)] = []

    init(shortcuts: BrowserShortcutStore, actions: @escaping () -> BrowserCommandActions?,
         perform: @escaping (BrowserShortcutCommand) -> Void,
         canPerform: @escaping (BrowserShortcutCommand) -> Bool,
         applicationAction: @escaping (ApplicationAction) -> Void,
         canCheckForUpdates: @escaping () -> Bool) {
        self.shortcuts = shortcuts
        self.actions = actions
        self.perform = perform
        self.canPerform = canPerform
        self.applicationAction = applicationAction
        self.canCheckForUpdates = canCheckForUpdates
    }

    func install() {
        let bar = NSMenu()
        let app = submenu("Crest", in: bar)
        special("About Crest", .about, in: app)
        special("Check for Updates…", .updates, in: app)
        app.addItem(.separator())
        special("Settings…", .settings, in: app, key: ",")
        let services = submenu("Services", in: app)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        standard("Hide Crest", "hide:", key: "h", in: app, target: NSApp)
        standard("Hide Others", "hideOtherApplications:", key: "h", modifiers: [.command, .option], in: app, target: NSApp)
        standard("Show All", "unhideAllApplications:", in: app, target: NSApp)
        app.addItem(.separator())
        standard("Quit Crest", "terminate:", key: "q", in: app, target: NSApp)

        let file = submenu("File", in: bar)
        commands([.newWindow, .newBlankWindow, .newTab, .newQuickWindow, .newPrivateWindow,
                  nil, .openFile, nil, .closeTabOrWindow, .closeWindow, nil, .printPage], in: file)
        let edit = submenu("Edit", in: bar)
        standard("Undo", "undo:", key: "z", in: edit)
        standard("Redo", "redo:", key: "z", modifiers: [.command, .shift], in: edit)
        edit.addItem(.separator())
        standard("Cut", "cut:", key: "x", in: edit)
        standard("Copy", "copy:", key: "c", in: edit)
        standard("Paste", "paste:", key: "v", in: edit)
        standard("Paste and Match Style", "pasteAsPlainText:", key: "v", modifiers: [.command, .option, .shift], in: edit)
        standard("Delete", "delete:", in: edit)
        standard("Select All", "selectAll:", key: "a", in: edit)

        let view = submenu("View", in: bar)
        commands([.toggleSidebar, nil, .showHistory, .showArchive, .showDownloads], in: view)
        view.addItem(.separator())
        standard("Enter Full Screen", "toggleFullScreen:", key: "f", modifiers: [.command, .control], in: view)
        commands([.openLocation, nil, .back, .forward, .reloadPage, .stopLoading, .reloadFromOrigin],
                 in: submenu("Navigate", in: bar))
        let tabs = submenu("Tabs", in: bar)
        commands([.toggleSelectedTabPinned, .duplicateTab, .reopenClosedTab, .clearUnpinnedTabs, .archiveTab,
                  nil, .previousTab, .nextTab, .mostRecentTab, nil, .splitWithNextTab,
                  .focusNextSplitCard, .focusPreviousSplitCard, .moveSplitCardLeft, .moveSplitCardRight,
                  .removeTabFromSplit, .separateSplitTabs, nil], in: tabs)
        commands((1...9).compactMap(BrowserShortcutCommand.tabSelection).map(Optional.some), in: tabs)
        let spaces = submenu("Spaces", in: bar)
        commands([.previousSpace, .nextSpace, nil], in: spaces)
        commands((1...9).compactMap(BrowserShortcutCommand.spaceSelection).map(Optional.some), in: spaces)
        // Reader, whole-page Apple translation and Crest's own content blocking have
        // no Chromium adapter. Their items are absent rather than permanently dimmed;
        // selection translation stays on Chromium's own page context menu, and broader
        // blocking comes from an extension.
        commands([.findInPage, nil, .zoomIn, .zoomOut, .actualSize, nil, .copyPageLink,
                  .copyPageLinkAsMarkdown, .sharePage, .exportPDF, .saveWebArchive],
                 in: submenu("Page", in: bar))
        commands([.toggleDeveloperToolbar, nil, .showWebInspector], in: submenu("Develop", in: bar))
        let window = submenu("Window", in: bar)
        standard("Minimize", "performMiniaturize:", key: "m", in: window)
        standard("Zoom", "performZoom:", in: window)
        window.addItem(.separator())
        standard("Bring All to Front", "arrangeInFront:", in: window, target: NSApp)
        NSApp.windowsMenu = window
        let help = submenu("Help", in: bar)
        special("Getting Started with Crest", .gettingStarted, in: help)
        NSApp.helpMenu = help
        NSApp.mainMenu = bar
        observeShortcuts()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshBindings() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let value = item.representedObject as? String else { return true }
        if let command = BrowserShortcutCommand(rawValue: value) {
            let context = actions()
            switch command {
            case .toggleDeveloperToolbar: item.state = context?.pages.activePage?.isDeveloperModeEnabled == true ? .on : .off
            default: break
            }
            return canPerform(command)
        }
        if value == ApplicationAction.updates.rawValue { return canCheckForUpdates() }
        return true
    }

    @objc private func runCommand(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String,
            let command = BrowserShortcutCommand(rawValue: value), canPerform(command) else { return }
        perform(command)
    }

    @objc private func runApplicationAction(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String,
            let action = ApplicationAction(rawValue: value) else { return }
        applicationAction(action)
    }

    private func observeShortcuts() {
        withObservationTracking {
            refreshBindings()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeShortcuts() }
        }
    }

    private func refreshBindings() {
        for (command, item) in commandItems {
            let shortcut = shortcuts.shortcut(for: command)
            item.keyEquivalent = shortcut.map { String($0.key.keyEquivalent.character) } ?? ""
            item.keyEquivalentModifierMask = shortcut?.modifiers.appKitModifierFlags ?? []
        }
    }

    private func commands(_ commands: [BrowserShortcutCommand?], in menu: NSMenu) {
        for command in commands {
            guard let command else { menu.addItem(.separator()); continue }
            let title: String
            switch command {
            case .toggleSelectedTabPinned: title = String(localized: "Pin or Unpin Tab")
            case .reopenClosedTab: title = String(localized: "Reopen Closed Tab")
            case .toggleDeveloperToolbar: title = String(localized: "Show Developer Toolbar")
            case .openFile: title = String(localized: "Open File…")
            case .toggleSidebar: title = String(localized: "Toggle Sidebar")
            case .printPage: title = String(localized: "Print…")
            case .sharePage: title = String(localized: "Share…")
            case .exportPDF: title = String(localized: "Export as PDF…")
            case .saveWebArchive: title = String(localized: "Save Web Archive…")
            default: title = command.title
            }
            let item = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: command.paletteSymbol, accessibilityDescription: nil)
            item.target = self
            item.representedObject = command.rawValue
            menu.addItem(item)
            commandItems.append((command, item))
        }
    }

    private func special(_ title: String, _ action: ApplicationAction, in menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: String(localized: String.LocalizationValue(title)),
            action: #selector(runApplicationAction(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = action.rawValue
        menu.addItem(item)
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let title = String(localized: String.LocalizationValue(title))
        let menu = NSMenu(title: title)
        menu.delegate = self
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    private func standard(_ title: String, _ selector: String, key: String = "",
                          modifiers: NSEvent.ModifierFlags = .command, in menu: NSMenu, target: AnyObject? = nil) {
        let item = NSMenuItem(title: String(localized: String.LocalizationValue(title)),
            action: NSSelectorFromString(selector), keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
}
#endif
