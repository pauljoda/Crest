import SwiftUI

/// Actual sidebar components, with all actions contained in a memory-only Space.
///
/// The sample Space carries one of everything the appearance settings act on:
/// pins with site colors, a folder of saved tabs, a loose saved tab, loose open
/// tabs, and a Split View group. Rows select and hover so the choices show, and
/// nothing else — the sidebar here is for looking at, so it declines to be
/// rearranged or organized.
struct BrowserSidebarCustomizationPreview: View {
    var space: BrowserSpace? = nil
    var showsPins = true
    var showsCurrentTabs = true
    var followsHighlightPreference = true
    /// Whether the preview draws the Space's atmosphere behind itself. The
    /// window crop already stands on that atmosphere, so it asks for the
    /// sidebar's contents alone.
    var showsBackground = true
    @State private var sample = BrowserAppearancePreviewState()
    @State private var editingFolder: BrowserFolderRuntimeAssignment?

    var body: some View {
        let preview = sample.space
        let tabSections = BrowserTabSections(tabs: preview.tabs)
        VStack(spacing: 8) {
            if showsPins {
                PinnedTabGrid(
                    tabs: preview.pinnedTabs, assignment: sample.assignment,
                    selectedTabID: preview.selectedTabID,
                    select: { sample.browser.selectTab($0.tabID) },
                    browser: sample.browser, spaceAccess: sample.spaceAccess,
                    siteThemeAccent: sample.siteThemeAccent,
                    capabilities: sample.capabilities
                )
                .padding(.horizontal, 8)
            }
            BrowserSavedTabsDropSection(
                space: preview, tabSections: tabSections,
                browser: sample.browser, spaceAccess: sample.spaceAccess,
                pageAccess: sample.pageAccess, tabActions: sample.tabActions,
                capabilities: sample.capabilities, restoreSavedLocation: { _ in },
                select: sample.browser.selectTab, editingFolderRequest: $editingFolder)
            if showsCurrentTabs {
                BrowserCurrentTabsDropSection(
                    space: preview, tabSections: tabSections,
                    browser: sample.browser, spaceAccess: sample.spaceAccess,
                    pageAccess: sample.pageAccess, tabActions: sample.tabActions,
                    capabilities: sample.capabilities,
                    select: sample.browser.selectTab, openNewTab: {})
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: BrowserChromeLayout.sidebarMaximumWidth)
        .background { background(for: preview.branding) }
        .clipShape(.rect(cornerRadius: showsBackground ? 14 : 0))
        .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: preview.branding))
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: preview, isUnlocked: true))
        .environment(\.folderPreviewShowsHighlight, !followsHighlightPreference)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interactive sidebar preview")
        .onChange(of: space, initial: true) { _, space in sample.applyTheme(space) }
    }

    @ViewBuilder
    private func background(for branding: BrowserSpaceBranding) -> some View {
        if showsBackground {
            BrowserSpaceBannerBackground(branding: branding)
        }
    }
}

@MainActor
private final class BrowserAppearancePreviewState {
    let browser: BrowserStore
    let spaceAccess = BrowserSpaceAccessController()
    let downloads = BrowserDownloadCenter(
        permissionCenter: BrowserSitePermissionCenter(persistence: InMemoryBrowserSitePermissionPersistence()))
    let capabilities = BrowserInteractionCapabilities(
        supportsTouch: BrowserSidebarDensityPolicy.usesTouch,
        pairsRowWithPromotedSurface: false,
        supportsOrganization: false)
    /// The color each sample site would hand its pin, keyed the way the shipping
    /// sidebar asks for it.
    private let siteAccents: [TabID: BrowserTabIconAccent]

    init() {
        let folder = BrowserFolder(title: String(localized: "Example folder"), symbol: "book.closed")
        let reading = BrowserTab(
            title: String(localized: "Reading list"), url: URL(string: "https://preview.invalid/reading"),
            symbol: "book.closed", placement: .saved, folderID: folder.id)
        let plans = BrowserTab(
            title: String(localized: "Weekend plans"), url: URL(string: "https://preview.invalid/plans"),
            symbol: "sun.max", placement: .saved, folderID: folder.id)
        let recipes = BrowserTab(
            title: String(localized: "Recipes"), url: URL(string: "https://preview.invalid/recipes"),
            symbol: "fork.knife", placement: .saved)
        let pinSources: [(String, String, BrowserTabIconAccent)] = [
            ("Calendar", "calendar", BrowserTabIconAccent(red: 0.93, green: 0.30, blue: 0.24)),
            ("Mail", "envelope.fill", BrowserTabIconAccent(red: 0.20, green: 0.52, blue: 0.96)),
            ("Music", "music.note", BrowserTabIconAccent(red: 0.98, green: 0.28, blue: 0.52)),
            ("Books", "book.fill", BrowserTabIconAccent(red: 0.96, green: 0.60, blue: 0.14)),
        ]
        let pins = pinSources.map { title, symbol, accent in
            BrowserTab(
                title: title, url: URL(string: "https://preview.invalid/" + title.lowercased()),
                symbol: symbol, iconAccent: accent, placement: .pinned)
        }
        let notes = BrowserTab(
            title: String(localized: "Meeting notes"), url: URL(string: "https://preview.invalid/notes"),
            symbol: "note.text", placement: .current)
        let tickets = BrowserTab(
            title: String(localized: "Flight tickets"), url: URL(string: "https://preview.invalid/tickets"),
            symbol: "airplane", placement: .current)
        let splitGroupID = SplitGroupID()
        let docs = BrowserTab(
            title: String(localized: "Draft"), url: URL(string: "https://preview.invalid/draft"),
            symbol: "doc.text", placement: .current, splitGroupID: splitGroupID)
        let research = BrowserTab(
            title: String(localized: "Research"), url: URL(string: "https://preview.invalid/research"),
            symbol: "magnifyingglass", placement: .current, splitGroupID: splitGroupID)
        var space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Preview", symbol: "paintpalette",
            accent: .indigo, branding: .house(.winter, symbol: "paintpalette"),
            folders: [folder], tabs: pins + [reading, plans, recipes, notes, tickets, docs, research],
            selectedTabID: notes.id)
        space.splitGroups = [BrowserSplitGroupMetadata(id: splitGroupID)]
        siteAccents = Dictionary(uniqueKeysWithValues: zip(pins.map(\.id), pinSources.map(\.2)))
        browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
            persistence: InMemoryBrowserSessionPersistence(), browsingMode: .privateBrowsing)
    }

    var space: BrowserSpace { browser.session.spaces[0] }
    var assignment: BrowserSpaceRuntimeAssignment { BrowserSpaceRuntimeAssignment(space: space) }

    func applyTheme(_ source: BrowserSpace?) {
        guard let source else { return }
        browser.session.spaces[0].branding = source.branding
        if let folder = source.folders.first {
            browser.session.spaces[0].folders[0].color = folder.color
            browser.session.spaces[0].folders[0].symbol = folder.symbol
        }
    }

    var siteThemeAccent: @Sendable (BrowserTabRuntimeAssignment) -> BrowserTabIconAccent? {
        { [siteAccents] assignment in siteAccents[assignment.tabID] }
    }

    var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(
            containsResidentPage: { _ in true }, containsResidentPageMatching: { _ in true },
            siteThemeIconAccent: siteThemeAccent, residencyRevision: { 0 }, selectPages: {},
            deactivatePagePresentation: {},
            unloadPage: { _, _ in }, pullFavicon: { _, _ in nil }, downloadCenter: downloads)
    }

    var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: assignment, browser: browser, spaceAccess: spaceAccess,
            syncPagesAfterMutation: {}, pullFavicon: { _, _ in nil })
    }
}
