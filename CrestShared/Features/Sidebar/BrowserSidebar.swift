import SwiftUI

/// The sidebar both shells are: the Space selection flow, the utility surfaces'
/// scratch state, and the one destructive confirmation the sidebar can raise.
///
/// What the two shells never actually disagreed about is everything in here.
/// Selecting a Space walks the same four steps on both — refuse a no-op, move
/// the session, refuse a locked or vanished Space, then decide whether the page
/// follows now or once the pager comes to rest. The utility search text and
/// filter reset on every surface change; finished downloads are acknowledged
/// the moment the reader can see them. Those were two copies of the same code.
///
/// What the shells *do* disagree about is the layout around it — a switcher
/// under a clipped pager on one, chrome in both safe-area insets on the other —
/// so the shell builds that from `BrowserSidebarContext` rather than the root
/// composing chrome it would have to branch on.
struct BrowserSidebar<Content: View>: View {
    let browser: BrowserStore
    let pageAccess: BrowserSidebarPageAccess
    let spaceAccess: BrowserSpaceAccessController

    /// What the hosting shell can do. Resolved by the host and handed down
    /// unchanged, so every row under this sidebar answers to one value.
    let capabilities: BrowserInteractionCapabilities

    let utilityCoordinator: BrowserSidebarUtilityCoordinator
    let utilityPresentation: BrowserUtilityPresentationState
    let chromeActions: BrowserSidebarChromeActions

    /// Whether this shell keeps the selected Space's page on screen beside the
    /// sidebar. Where it does, changing Space brings the new Space's page up;
    /// where the sidebar *is* the screen, changing Space takes the page down
    /// and nothing is waiting on the pager.
    let presentsSelectedSpacePage: Bool

    /// Called once the session has moved, with the Space that ended up
    /// selected, or `nil` when it is locked or gone. This is where a shell that
    /// owns the address field brings it back in step; a shell whose root model
    /// already observes the session does nothing.
    let spaceSelectionChanged: (BrowserSpace?) -> Void

    @ViewBuilder let content: (BrowserSidebarContext) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingPageSelection: BrowserSpaceRuntimeAssignment?
    @State private var utilitySearchText = ""
    @State private var utilityFilter = BrowserUtilityListFilter.all
    @State private var clearHistoryConfirmation: BrowserSidebarClearHistoryConfirmation?

    init(
        browser: BrowserStore,
        pageAccess: BrowserSidebarPageAccess,
        spaceAccess: BrowserSpaceAccessController,
        capabilities: BrowserInteractionCapabilities,
        utilityCoordinator: BrowserSidebarUtilityCoordinator,
        utilityPresentation: BrowserUtilityPresentationState,
        chromeActions: BrowserSidebarChromeActions,
        presentsSelectedSpacePage: Bool = true,
        spaceSelectionChanged: @escaping (BrowserSpace?) -> Void = { _ in },
        @ViewBuilder content: @escaping (BrowserSidebarContext) -> Content
    ) {
        self.browser = browser
        self.pageAccess = pageAccess
        self.spaceAccess = spaceAccess
        self.capabilities = capabilities
        self.utilityCoordinator = utilityCoordinator
        self.utilityPresentation = utilityPresentation
        self.chromeActions = chromeActions
        self.presentsSelectedSpacePage = presentsSelectedSpacePage
        self.spaceSelectionChanged = spaceSelectionChanged
        self.content = content
    }

    var body: some View {
        content(context)
            .modifier(
                BrowserSidebarClearHistoryDialog(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    confirmation: $clearHistoryConfirmation
                )
            )
            .onChange(of: utilityPresentation.surface) { previous, current in
                if previous != current {
                    utilitySearchText = ""
                    utilityFilter = .all
                }
                utilityCoordinator.acknowledgeDownloads(ifPresented: current)
            }
            .onChange(of: selectedDownloadIDs) {
                utilityCoordinator.acknowledgeDownloads(
                    ifPresented: utilityPresentation.surface
                )
            }
    }

    private var context: BrowserSidebarContext {
        BrowserSidebarContext(
            browser: browser,
            pageAccess: pageAccess,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            availableSpaces: BrowserSidebarAccessPolicy.availableSpaces(
                in: browser
            ),
            utilityPresentation: utilityPresentation,
            utilityActions: utilityCoordinator.actions,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter,
            chromeActions: chromeActions,
            selectSpace: selectSpace,
            settleSpaceSelection: settleSpaceSelection,
            confirmClearHistory: confirmClearHistory(for:),
            dismissUtilityOnBlankSpace: dismissUtilityOnBlankSpace,
            toggleUtilitySwitcher: toggleUtilitySwitcher
        )
    }

    private var selectedDownloadIDs: [UUID] {
        utilityCoordinator.selectedDownloads.map(\.id)
    }

    private var newUtilityDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pageAccess.downloadCenter.unacknowledgedItems(for: profileID)
    }

    private func dismissUtilityOnBlankSpace() {
        utilityPresentation.handleInteraction(.sidebarBlankSpace)
    }

    private func toggleUtilitySwitcher() {
        utilityPresentation.toggleSwitcher(
            hasNewDownloads: !newUtilityDownloads.isEmpty
        )
    }

    private func confirmClearHistory(for space: BrowserSpace) {
        clearHistoryConfirmation =
            BrowserSidebarSpacePresentationPolicy.clearHistoryConfirmation(
                for: space,
                in: browser,
                accessController: spaceAccess
            )
    }

    /// Moves the session to a Space, then decides what the page layer does
    /// about it.
    ///
    /// A shell that has no page beside the sidebar takes the outgoing page down
    /// before the session moves, so nothing is briefly showing one Space's page
    /// under another Space's tabs.
    private func selectSpace(_ spaceID: SpaceID) {
        guard spaceID != browser.session.selectedSpaceID else { return }
        if !presentsSelectedSpacePage {
            pageAccess.deactivatePagePresentation()
        }
        browser.selectSpace(spaceID)
        guard let space = selectedUnlockedSpace else {
            pendingPageSelection = nil
            pageAccess.deactivatePagePresentation()
            spaceSelectionChanged(nil)
            return
        }
        spaceSelectionChanged(space)
        guard presentsSelectedSpacePage else {
            pendingPageSelection = nil
            return
        }
        guard
            BrowserSpaceContentSelectionPolicy.defersWebContentUntilPagerSettles,
            !reduceMotion
        else {
            pageAccess.selectPages()
            return
        }
        pendingPageSelection = BrowserSpaceRuntimeAssignment(space: space)
    }

    /// Releases a deferred page selection once the pager has come to rest on
    /// the Space that asked for it, and drops the request outright when the
    /// reader landed somewhere else or the Space stopped being reachable.
    private func settleSpaceSelection(_ settledSpaceID: SpaceID) {
        guard let assignment = pendingPageSelection else { return }
        guard
            BrowserSidebarAccessPolicy.canSettlePageSelection(
                assignment,
                settledSpaceID: settledSpaceID,
                in: browser,
                accessController: spaceAccess
            )
        else {
            if settledSpaceID == assignment.spaceID
                || browser.session.selectedSpaceID != assignment.spaceID
            {
                pendingPageSelection = nil
                pageAccess.deactivatePagePresentation()
            }
            return
        }
        pendingPageSelection = nil
        pageAccess.selectPages()
    }

    private var selectedUnlockedSpace: BrowserSpace? {
        guard let space = browser.selectedSpace else { return nil }
        return BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: BrowserSpaceRuntimeAssignment(space: space),
            in: browser,
            accessController: spaceAccess
        )
    }
}

#Preview("Browser Sidebar — Space Pager") {
    let browser = BrowserSidebarPreviewFixture.makeBrowser()
    let spaceAccess = BrowserSidebarPreviewFixture.makeSpaceAccess()
    BrowserSidebar(
        browser: browser,
        pageAccess: BrowserSidebarPreviewFixture.makePageAccess(),
        spaceAccess: spaceAccess,
        capabilities: BrowserInteractionCapabilities(),
        utilityCoordinator: BrowserSidebarPreviewFixture.makeUtilityCoordinator(
            browser: browser,
            spaceAccess: spaceAccess
        ),
        utilityPresentation:
            BrowserSidebarPreviewFixture.makeUtilityPresentation(),
        chromeActions: BrowserSidebarPreviewFixture.makeChromeActions()
    ) { context in
        BrowserSidebarSpacePager(context: context) { space, isSelected in
            VStack {
                Text(space.name)
                    .font(.headline)
                Text("\(space.tabs.count) tabs")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isSelected ? 1 : 0.4)
        }
    }
    .frame(width: 280, height: 420)
}
