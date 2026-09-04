enum BrowserShortcutCommand:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case newWindow
    case newTab
    case newQuickWindow
    case newPrivateWindow
    case closeTabOrWindow
    case closeWindow
    case openLocation
    case back
    case forward
    case reloadPage
    case stopLoading
    case reloadFromOrigin
    case toggleSelectedTabPinned
    case duplicateTab
    case reopenClosedTab
    case clearUnpinnedTabs
    case archiveTab
    case previousTab
    case nextTab
    case mostRecentTab
    case selectTab1
    case selectTab2
    case selectTab3
    case selectTab4
    case selectTab5
    case selectTab6
    case selectTab7
    case selectTab8
    case selectTab9
    case previousSpace
    case nextSpace
    case selectSpace1
    case selectSpace2
    case selectSpace3
    case selectSpace4
    case selectSpace5
    case selectSpace6
    case selectSpace7
    case selectSpace8
    case selectSpace9
    case toggleReaderMode
    case toggleContentBlocking
    case findInPage
    case zoomIn
    case zoomOut
    case actualSize
    case copyPageLink
    case copyPageLinkAsMarkdown
    case sharePage
    case exportPDF
    case saveWebArchive
    case printPage
    case toggleSidebar
    case showHistory
    case showArchive
    case showDownloads
    case showWebInspector = "webInspectorInstructions"
    // Append-only: a raw value is a shipped persistence key, and the order
    // below is the order the shortcut settings list shows within a section.
    case splitWithNextTab
    case focusNextSplitCard
    case focusPreviousSplitCard
    case removeTabFromSplit
    case separateSplitTabs
    case moveSplitCardLeft
    case moveSplitCardRight
    case toggleExtensionSidePanel

    var id: Self { self }

    static let userFacingCases = allCases
}

extension BrowserShortcutCommand {
    var defaultShortcut: BrowserShortcut? {
        BrowserShortcutDefaultPolicy.shortcut(for: self)
    }

    static func tabSelection(_ number: Int) -> BrowserShortcutCommand? {
        BrowserShortcutNumberedSelectionPolicy.tabCommand(number)
    }

    static func spaceSelection(_ number: Int) -> BrowserShortcutCommand? {
        BrowserShortcutNumberedSelectionPolicy.spaceCommand(number)
    }

    var tabNumber: Int? {
        BrowserShortcutNumberedSelectionPolicy.tabNumber(for: self)
    }

    var spaceNumber: Int? {
        BrowserShortcutNumberedSelectionPolicy.spaceNumber(for: self)
    }

    var section: BrowserShortcutSection {
        BrowserShortcutSectionPolicy.section(for: self)
    }
}
