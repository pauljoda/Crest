import Foundation

struct BrowserShortcutPresentationCatalog: BrowserShortcutSearchProviding {
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func matches(
        _ command: BrowserShortcutCommand,
        currentShortcut: BrowserShortcut?,
        query: String
    ) -> Bool {
        BrowserShortcutSearchPolicy.matches(
            query: query,
            document: BrowserShortcutSearchDocument(
                fields: [
                    BrowserShortcutLocalization.string(
                        command.titleResource,
                        locale: locale
                    ),
                    BrowserShortcutLocalization.string(
                        command.section.titleResource,
                        locale: locale
                    ),
                    BrowserShortcutLocalization.string(
                        command.relatedSearchTermsResource,
                        locale: locale
                    ),
                    currentShortcut?.spokenDescription(locale: locale)
                        ?? BrowserShortcutLocalization.string(
                            "unassigned none no shortcut",
                            locale: locale
                        ),
                ]
            )
        )
    }

    func matches(
        _ command: BrowserShortcutExtensionCommand,
        query: String
    ) -> Bool {
        BrowserShortcutSearchPolicy.containsTrimmedPhrase(
            query: query,
            fields: [
                command.extensionDisplayName,
                command.title,
                command.commandID,
                command.shortcut?.displayString(locale: locale)
                    ?? BrowserShortcutLocalization.string(
                        "unassigned",
                        locale: locale
                    ),
                command.shortcut?.spokenDescription(locale: locale)
                    ?? BrowserShortcutLocalization.string(
                        "no shortcut",
                        locale: locale
                    ),
            ]
        )
    }
}

enum BrowserShortcutLocalization {
    static func string(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        String(localized: Self.resource(resource, locale: locale))
    }

    static func resource(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> LocalizedStringResource {
        var localizedResource = resource
        localizedResource.locale = locale
        return localizedResource
    }

    static func list(
        _ values: [String],
        locale: Locale
    ) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values)
            ?? values.joined(separator: ", ")
    }
}

extension BrowserShortcut {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        modifiers.displayString + key.displayString(locale: locale)
    }

    func spokenDescription(locale: Locale = .current) -> String {
        [
            modifiers.spokenDescription(locale: locale),
            key.spokenDescription(locale: locale),
        ].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension BrowserShortcutCommand {
    var titleResource: LocalizedStringResource {
        if let number = tabNumber {
            return "Select Tab \(number)"
        }
        if let number = spaceNumber {
            return "Select Space \(number)"
        }

        return switch self {
        case .newWindow: "New Window"
        case .newTab: "New Tab"
        case .newQuickWindow: "New Quick Window"
        case .newPrivateWindow: "New Private Window"
        case .closeTabOrWindow: "Close Current Tab or Window"
        case .closeWindow: "Close Window"
        case .openLocation: "Open Location"
        case .back: "Back"
        case .forward: "Forward"
        case .reloadPage: "Reload Page"
        case .stopLoading: "Stop Loading"
        case .reloadFromOrigin: "Reload from Origin"
        case .toggleSelectedTabPinned: "Pin or Unpin Current Tab"
        case .duplicateTab: "Duplicate Tab"
        case .reopenClosedTab: "Reopen Last Closed Tab"
        case .clearUnpinnedTabs: "Clear Unpinned Tabs"
        case .archiveTab: "Archive Tab"
        case .previousTab: "Previous Tab"
        case .nextTab: "Next Tab"
        case .mostRecentTab: "Most Recent Tab"
        case .previousSpace: "Previous Space"
        case .nextSpace: "Next Space"
        case .toggleReaderMode: "Show or Hide Reader"
        case .toggleContentBlocking: "Toggle Content Blocking"
        case .findInPage: "Find in Page"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        case .copyPageLink: "Copy Page Link"
        case .copyPageLinkAsMarkdown: "Copy Page Link as Markdown"
        case .sharePage: "Share Page"
        case .exportPDF: "Export as PDF"
        case .saveWebArchive: "Save Web Archive"
        case .printPage: "Print Page"
        case .toggleSidebar: "Show or Hide Sidebar"
        case .showHistory: "Show History"
        case .showArchive: "Show Archive"
        case .showDownloads: "Show Downloads"
        case .showWebInspector: "Show Web Inspector"
        case .splitWithNextTab: "Split With Next Tab"
        case .focusNextSplitCard: "Focus Next Split Card"
        case .focusPreviousSplitCard: "Focus Previous Split Card"
        case .removeTabFromSplit: "Remove Tab From Split"
        case .separateSplitTabs: "Separate All Tabs"
        case .moveSplitCardLeft: "Move Split Card Left"
        case .moveSplitCardRight: "Move Split Card Right"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4,
            .selectSpace5, .selectSpace6, .selectSpace7, .selectSpace8,
            .selectSpace9:
            preconditionFailure("Numbered shortcuts resolve before this switch")
        }
    }

    var title: String {
        title()
    }

    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(titleResource, locale: locale)
    }

    func matches(search query: String) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: defaultShortcut,
            query: query
        )
    }

    func matches(
        search query: String,
        currentShortcut: BrowserShortcut?
    ) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: currentShortcut,
            query: query
        )
    }

    var relatedSearchTermsResource: LocalizedStringResource {
        switch self {
        case .copyPageLink: "copy url address clipboard"
        case .copyPageLinkAsMarkdown: "copy url address markdown clipboard"
        case .openLocation: "change current tab url address focus"
        case .closeTabOrWindow: "close archive current tab window"
        case .clearUnpinnedTabs: "clean tidy archive unpinned tabs"
        case .mostRecentTab: "toggle recent switch tabs"
        case .previousTab, .nextTab: "switch cycle tabs up down arrow"
        case .previousSpace, .nextSpace:
            "switch cycle spaces left right arrow"
        case .toggleSelectedTabPinned: "favorite bookmark pin unpin"
        case .newPrivateWindow: "incognito private browsing"
        case .newQuickWindow: "little arc quick lookup"
        case .showHistory: "visited pages history"
        case .showArchive: "closed tabs archive"
        case .showDownloads: "download files transfers"
        case .toggleReaderMode: "reader reading mode"
        case .toggleContentBlocking: "ads trackers privacy protection"
        case .actualSize: "reset zoom zero"
        case .showWebInspector:
            "developer tools inspect element webkit safari"
        case .splitWithNextTab: "split view cards side by side columns"
        case .focusNextSplitCard, .focusPreviousSplitCard:
            "split view cards focus cycle left right arrow"
        case .removeTabFromSplit: "split view card remove leave unsplit"
        case .separateSplitTabs: "split view break up unsplit separate cards"
        case .moveSplitCardLeft, .moveSplitCardRight:
            "split view cards move reorder rearrange left right arrow"
        default: ""
        }
    }
}

extension BrowserShortcutKey {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).uppercased()
        case .special(let key):
            key.displayString(locale: locale)
        }
    }

    func spokenDescription(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).lowercased()
        case .special(let key):
            key.spokenDescription(locale: locale)
        }
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension BrowserShortcutModifiers {
    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    func spokenDescription(locale: Locale = .current) -> String {
        let resources: [LocalizedStringResource] = [
            contains(.control) ? "control" : nil,
            contains(.option) ? "option" : nil,
            contains(.shift) ? "shift" : nil,
            contains(.command) ? "command" : nil,
        ].compactMap { $0 }
        return resources.map { resource in
            BrowserShortcutLocalization.string(resource, locale: locale)
        }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension BrowserShortcutSection {
    var titleResource: LocalizedStringResource {
        switch self {
        case .everyday: "Everyday Use"
        case .tabs: "Tabs"
        case .spaces: "Spaces"
        case .page: "Page"
        case .view: "View & Tools"
        }
    }

    var title: String {
        title()
    }

    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(titleResource, locale: locale)
    }
}

extension BrowserShortcutSpecialKey {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        switch self {
        case .tab: "⇥"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .escape: "⎋"
        case .returnKey: "↩"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .space:
            BrowserShortcutLocalization.string("Space", locale: locale)
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        case .f13: "F13"
        case .f14: "F14"
        case .f15: "F15"
        case .f16: "F16"
        case .f17: "F17"
        case .f18: "F18"
        case .f19: "F19"
        case .f20: "F20"
        }
    }

    func spokenDescription(locale: Locale = .current) -> String {
        guard let resource = spokenDescriptionResource else { return rawValue }
        return BrowserShortcutLocalization.string(resource, locale: locale)
    }

    var spokenDescription: String {
        spokenDescription()
    }

    private var spokenDescriptionResource: LocalizedStringResource? {
        switch self {
        case .tab: "tab"
        case .leftArrow: "left arrow"
        case .rightArrow: "right arrow"
        case .upArrow: "up arrow"
        case .downArrow: "down arrow"
        case .escape: "escape"
        case .returnKey: "return"
        case .delete: "delete"
        case .forwardDelete: "forward delete"
        case .home: "home"
        case .end: "end"
        case .pageUp: "page up"
        case .pageDown: "page down"
        case .space: "space"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            nil
        }
    }
}

extension BrowserShortcutStore {
    func commands(matching query: String) -> [BrowserShortcutCommand] {
        let catalog = BrowserShortcutPresentationCatalog()
        return BrowserShortcutCommand.userFacingCases.filter {
            catalog.matches(
                $0,
                currentShortcut: shortcut(for: $0),
                query: query
            )
        }
    }
}
