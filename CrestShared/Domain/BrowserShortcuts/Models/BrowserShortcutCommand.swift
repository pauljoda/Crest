enum BrowserShortcutCommand:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case newWindow
    case newBlankWindow
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
    case toggleDeveloperToolbar
    case toggleTranslationToolbar
    case openFile

    var id: Self { self }

    /// The commands this process offers anywhere a person can find one: the
    /// menu bar, the launcher and the shortcut settings list. A command whose
    /// whole feature the running engine declares absent is left out rather
    /// than shown permanently dimmed, and it cannot claim a chord either.
    static let userFacingCases = allCases.filter { $0.isOffered(by: BrowserEngineRegistration.current) }
}

extension BrowserShortcutCommand {
    /// The engine capability a command's entire feature depends on.
    ///
    /// Only features an engine may lack outright belong here. Document actions
    /// such as printing or export stay listed and are dimmed through the
    /// page's own capability when the active page cannot perform them.
    var requiredEngineCapability: BrowserEngineCapability? {
        switch self {
        case .toggleReaderMode: .reader
        case .toggleContentBlocking: .contentBlocking
        case .toggleTranslationToolbar: .translation
        default: nil
        }
    }

    func isOffered(by registration: BrowserAdapterRegistration) -> Bool {
        requiredEngineCapability.map(registration.supports) ?? true
    }

    var isOfferedByCurrentEngine: Bool {
        isOffered(by: BrowserEngineRegistration.current)
    }

    /// Crest's default chord, from the core's catalog.
    var defaultShortcut: BrowserShortcut? {
        BrowserCorePolicy.defaultShortcuts[self]
    }

    // The numbered commands' labels. What each one selects is the core's
    // `shortcuts.numbered_selection` rule.
    private static let tabSelections: [Self] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    private static let spaceSelections: [Self] = [
        .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4, .selectSpace5,
        .selectSpace6, .selectSpace7, .selectSpace8, .selectSpace9,
    ]

    static func tabSelection(_ number: Int) -> BrowserShortcutCommand? {
        tabSelections.indices.contains(number - 1) ? tabSelections[number - 1] : nil
    }

    static func spaceSelection(_ number: Int) -> BrowserShortcutCommand? {
        spaceSelections.indices.contains(number - 1) ? spaceSelections[number - 1] : nil
    }

    var tabNumber: Int? {
        Self.tabSelections.firstIndex(of: self).map { $0 + 1 }
    }

    var spaceNumber: Int? {
        Self.spaceSelections.firstIndex(of: self).map { $0 + 1 }
    }

    var section: BrowserShortcutSection {
        BrowserShortcutSectionPolicy.section(for: self)
    }
}
