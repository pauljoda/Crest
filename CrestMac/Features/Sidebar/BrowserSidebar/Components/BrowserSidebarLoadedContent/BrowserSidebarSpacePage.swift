import SwiftUI

struct BrowserSidebarSpacePage: View {
    let space: BrowserSpace
    let isSelected: Bool
    let pages: BrowserPagePool
    let openNewTab: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    // Cache only this page's inputs, not the root context's complete Space
    // collection and unrelated sidebar actions. Re-initialization still
    // supplies fresh owners, bindings and callbacks on every root update.
    private let browser: BrowserStore
    private let spaceAccess: BrowserSpaceAccessController
    private let capabilities: BrowserInteractionCapabilities
    private let chromeActions: BrowserSidebarChromeActions
    private let utilityPresentation: BrowserUtilityPresentationState
    private let utilityActions: BrowserUtilityListActions
    private let utilitySearchText: Binding<String>
    private let utilityFilter: Binding<BrowserUtilityListFilter>
    private let downloadCenter: BrowserDownloadCenter
    private let dismissUtilityOnBlankSpace: () -> Void
    private let confirmClearHistory: (BrowserSpace) -> Void

    init(
        space: BrowserSpace,
        isSelected: Bool,
        context: BrowserSidebarContext,
        pages: BrowserPagePool,
        openNewTab: @escaping () -> Void,
        commandSurfaceNamespace: Namespace.ID,
        tabPromotionNamespace: Namespace.ID
    ) {
        self.space = space
        self.isSelected = isSelected
        self.pages = pages
        self.openNewTab = openNewTab
        self.commandSurfaceNamespace = commandSurfaceNamespace
        self.tabPromotionNamespace = tabPromotionNamespace
        browser = context.browser
        spaceAccess = context.spaceAccess
        capabilities = context.capabilities
        chromeActions = context.chromeActions
        utilityPresentation = context.utilityPresentation
        utilityActions = context.utilityActions
        utilitySearchText = context.utilitySearchText
        utilityFilter = context.utilityFilter
        downloadCenter = context.pageAccess.downloadCenter
        dismissUtilityOnBlankSpace = context.dismissUtilityOnBlankSpace
        confirmClearHistory = context.confirmClearHistory
    }

    private var isLocked: Bool {
        spaceAccess.isLocked(space)
    }

    var body: some View {
        // These callbacks use the page and their action owners, independently
        // of the selected role that changes on the surrounding native host.
        let pageSpace = space
        let actions = chromeActions
        let confirmClear = confirmClearHistory
        SpaceSidebarContent(
            space: space,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            openNewTab: openNewTab,
            showHistory: chromeActions.presentHistory,
            showExtensions: { actions.presentExtensions?(pageSpace) },
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            editSpace: { actions.presentSpaceSettings(pageSpace) },
            createSpace: { actions.createSpace?() },
            utilitySurface: utilityPresentation.surface,
            utilitySearchText: utilitySearchText,
            utilityFilter: utilityFilter,
            utilityDownloads: downloadCenter.items(
                for: space.profile.id
            ),
            utilityActions: utilityActions,
            dismissUtilityOnBlankSpace: dismissUtilityOnBlankSpace,
            clearHistory: { confirmClear(pageSpace) }
        )
        .environment(
            \.sidebarSpacePresentation,
            SidebarSpacePresentation(space: space, isUnlocked: !isLocked)
        )
        .environment(\.sidebarSpaceIsSelected, isSelected)
        .onChange(of: isLocked) { _, locked in
            if locked, isSelected { browser.tabMultiSelection.clear() }
        }
        .environment(
            \.colorScheme,
            BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
        )
        .blur(
            radius: isLocked
                ? BrowserSidebarMetrics.lockedSpaceBlurRadius
                : 0
        )
        .redacted(reason: isLocked ? .placeholder : [])
        .allowsHitTesting(isSelected && !isLocked)
        // Retained offscreen pages must not participate when AppKit rebuilds
        // keyboard navigation for a newly focused Start Page command field.
        // An empty interaction set avoids adding a focus stop for the container.
        .focusable(isSelected && !isLocked, interactions: [])
        .accessibilityHidden(!isSelected || isLocked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(space.name) Space")
    }

}
