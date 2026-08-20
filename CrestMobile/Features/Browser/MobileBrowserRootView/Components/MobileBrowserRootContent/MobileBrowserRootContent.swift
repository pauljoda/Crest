import SwiftUI
import UIKit

struct MobileBrowserRootContent: View, BrowserChromeAnimating {
    let model: MobileBrowserRootModel
    let dataDeleter: any BrowserSpaceDataDeleting
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let suspendsCompactPagePresentation: Bool
    let togglePrivateBrowsing: () -> Void
    let closePrivateBrowsing: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.layoutDirection) var layoutDirection
    @State var isAddressEditing = false
    @State var addressFocusRequest = 0
    @State var commandPaletteMode: BrowserCommandPaletteMode?
    @State var historyAssignment: BrowserSpaceRuntimeAssignment?
    @State var isURLCopiedFeedbackVisible = false
    @State var visiblePageZoomFeedbackLabel: String?
    @State var storedRegularSidebarWidth: Double
    @State var availableRootSize = CGSize.zero
    @State var keyboardEndFrame = CGRect.null
    @AppStorage(MobileCollapsedSidebarFullscreenPreference.key)
    var collapsedSidebarFullscreenIsEnabled = false
    @Namespace var compactChromeNamespace
    @Namespace var tabPromotionNamespace

    init(
        model: MobileBrowserRootModel,
        dataDeleter: any BrowserSpaceDataDeleting,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        suspendsCompactPagePresentation: Bool,
        togglePrivateBrowsing: @escaping () -> Void,
        closePrivateBrowsing: @escaping () -> Void
    ) {
        self.model = model
        self.dataDeleter = dataDeleter
        self.transientBrowsing = transientBrowsing
        self.suspendsCompactPagePresentation = suspendsCompactPagePresentation
        self.togglePrivateBrowsing = togglePrivateBrowsing
        self.closePrivateBrowsing = closePrivateBrowsing
        _storedRegularSidebarWidth = State(
            initialValue: Double(model.sidebarWidth)
        )
    }

    var body: some View {
        MobileBrowserRootSurface(
            presentation: presentation,
            browser: browser,
            pages: pages,
            navigation: navigation,
            transientBrowsing: transientBrowsing,
            spaceAccess: spaceAccess,
            preferredSidebarWidth: model.sidebarWidth,
            isCommandPalettePresented: commandPaletteMode != nil,
            isURLCopiedFeedbackVisible: isURLCopiedFeedbackVisible,
            pageZoomFeedbackLabel: visiblePageZoomFeedbackLabel,
            reduceMotion: reduceMotion,
            didPromoteTransientPage: model.activateSelectedTab,
            compact: MobileCompactBrowserSurface(
                compactShowsPage: navigation.compactShowsPage,
                isPagePresented: compactPagePresentation,
                usesDockedDetailPresentation:
                    navigation.regularSidebarIsDocked,
                sidebarPresentation: navigation.regularSidebarPresentation,
                preferredSidebarWidth: model.sidebarWidthBinding,
                space: browser.selectedSpace,
                reduceTransparency: reduceTransparency,
                layoutDirection: layoutDirection,
                usesBorderlessFloatingPageFrame:
                    usesCollapsedSidebarBorderlessFrame,
                isStartPage: browser.selectedTab?.isStartPage == true,
                hasActivePage: model.selectedPage != nil,
                hasSelectedSpace: browser.selectedSpace != nil,
                showSidebar: showRegularSidebar,
                commitSidebarWidth: commitRegularSidebarWidth,
                dockedSidebar: MobileBrowserSidebarSurface(
                    browser: browser,
                    pages: pages,
                    dataDeleter: dataDeleter,
                    spaceAccess: spaceAccess,
                    utilityPresentationStyle: .sheet,
                    showsPageBackdrop: true,
                    reservesBottomChromeInset: true,
                    presentsSelectedSpacePage: false,
                    sidebarToggleUndocks: true,
                    usesNativeNavigationTransition: true,
                    compactChromeNamespace: compactChromeNamespace,
                    tabPromotionNamespace: tabPromotionNamespace,
                    address: model.addressBinding,
                    isAddressEditing: $isAddressEditing,
                    activateAddress: openLocation,
                    selectTab: selectTab,
                    submitAddress: submitAddress,
                    openURL: openURL,
                    openNewTab: beginNewTab,
                    showsCompactAddressBar:
                        MobileCompactTabViewerLayout.showsTopAddressBar,
                    showsBottomSpaceSwitcher:
                        navigation.compactTabViewerChromeIsVisible,
                    compactPageIsFullyPresented:
                        navigation.compactPageIsFullyPresented,
                    compactTransitionEnded: finishCompactTransition,
                    togglePrivateBrowsing: togglePrivateBrowsing,
                    closePrivateBrowsing: closePrivateBrowsing,
                    toggleSidebar: toggleCompactSidebar,
                    showsSidebarToggle: true,
                    sidebarIsDocked: true,
                    utilityPresentation: navigation.utilityPresentation
                ),
                floatingSidebar: MobileBrowserSidebarSurface(
                    browser: browser,
                    pages: pages,
                    dataDeleter: dataDeleter,
                    spaceAccess: spaceAccess,
                    utilityPresentationStyle: .inline,
                    showsPageBackdrop: false,
                    reservesBottomChromeInset: false,
                    presentsSelectedSpacePage: true,
                    sidebarToggleUndocks: false,
                    usesNativeNavigationTransition: false,
                    compactChromeNamespace: compactChromeNamespace,
                    tabPromotionNamespace: tabPromotionNamespace,
                    address: model.addressBinding,
                    isAddressEditing: $isAddressEditing,
                    activateAddress: openLocation,
                    selectTab: selectTab,
                    submitAddress: submitAddress,
                    openURL: openURL,
                    openNewTab: beginNewTab,
                    showsCompactAddressBar: false,
                    showsBottomSpaceSwitcher: true,
                    compactPageIsFullyPresented: false,
                    compactTransitionEnded: finishCompactTransition,
                    togglePrivateBrowsing: togglePrivateBrowsing,
                    closePrivateBrowsing: closePrivateBrowsing,
                    toggleSidebar: toggleCompactSidebar,
                    showsSidebarToggle: true,
                    sidebarIsDocked: false,
                    utilityPresentation: navigation.utilityPresentation
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        navigation.handleRegularSidebarInteraction()
                    }
                )
                // Never zero: this rides over the rows, and a drag that begins
                // on touch-down takes the press the reorder lift needs.
                .simultaneousGesture(
                    DragGesture(
                        minimumDistance: MobileBrowserChromeLayout
                            .transientSidebarKeepAliveDistance
                    ).onChanged { _ in
                        navigation.handleRegularSidebarInteraction()
                    }
                ),
                page: MobileCompactPageSurface(
                    browser: browser,
                    pages: pages,
                    transientBrowsing: transientBrowsing,
                    spaceAccess: spaceAccess,
                    selectedTab: browser.selectedTab,
                    isURLCopiedFeedbackVisible: isURLCopiedFeedbackVisible,
                    pageZoomFeedbackLabel: visiblePageZoomFeedbackLabel,
                    reduceMotion: reduceMotion,
                    didPromoteTransientPage: model.activateSelectedTab,
                    tabPromotionNamespace: tabPromotionNamespace,
                    completePagePresentation:
                        navigation.completePagePresentation,
                    backdrop: MobileCompactPageBackdrop(
                        isStartPage:
                            browser.selectedTab?.isStartPage == true,
                        hasSelectedPage: model.selectedPage != nil,
                        pageThemeColor: model.selectedPage?.themeColor,
                        underPageBackgroundColor:
                            model.selectedPage?.webView
                            .underPageBackgroundColor,
                        space: browser.selectedSpace
                    ),
                    detail: MobileBrowserDetailSurface(
                        browser: browser,
                        pages: pages,
                        spaceAccess: spaceAccess,
                        address: model.addressBinding,
                        isAddressEditing: $isAddressEditing,
                        addressFocusRequest: addressFocusRequest,
                        isCommandPalettePresented:
                            commandPaletteMode != nil,
                        isCompact: true,
                        obscuresSystemSafeAreas:
                            usesCollapsedSidebarBorderlessFrame,
                        showsCompactToolbar: showsCompactPageToolbar,
                        compactToolbarIsHidden:
                            navigation.compactToolbarIsHidden,
                        handleWebContentInteraction:
                            navigation.handleRegularPageInteraction,
                        submitAddress: submitAddress,
                        beginNewTab: beginNewTab,
                        showTabViewer: showTabViewer,
                        hideCompactToolbar:
                            navigation.hideCompactToolbar,
                        showCompactToolbar:
                            navigation.showCompactToolbar,
                        handleToolbarSwipe: handleToolbarSwipe,
                        selectSplitCard: selectSplitCard,
                        compactTransitionEnded: finishCompactTransition
                    )
                )
            ),
            regular: { layout in
                MobileRegularBrowserLayout(
                    layout: layout,
                    sidebarPresentation:
                        navigation.regularSidebarPresentation,
                    preferredSidebarWidth: model.sidebarWidthBinding,
                    reduceTransparency: reduceTransparency,
                    layoutDirection: layoutDirection,
                    space: browser.selectedSpace,
                    showSidebar: showRegularSidebar,
                    commitSidebarWidth: commitRegularSidebarWidth,
                    sidebar: MobileBrowserSidebarSurface(
                        browser: browser,
                        pages: pages,
                        dataDeleter: dataDeleter,
                        spaceAccess: spaceAccess,
                        utilityPresentationStyle: .inline,
                        showsPageBackdrop: false,
                        reservesBottomChromeInset: false,
                        presentsSelectedSpacePage: true,
                        sidebarToggleUndocks: false,
                        usesNativeNavigationTransition: false,
                        compactChromeNamespace: compactChromeNamespace,
                        tabPromotionNamespace: tabPromotionNamespace,
                        address: model.addressBinding,
                        isAddressEditing: $isAddressEditing,
                        activateAddress: openLocation,
                        selectTab: selectTab,
                        submitAddress: submitAddress,
                        openURL: openURL,
                        openNewTab: beginNewTab,
                        showsCompactAddressBar: false,
                        showsBottomSpaceSwitcher: true,
                        compactPageIsFullyPresented: false,
                        compactTransitionEnded: finishCompactTransition,
                        togglePrivateBrowsing: togglePrivateBrowsing,
                        closePrivateBrowsing: closePrivateBrowsing,
                        toggleSidebar: toggleRegularSidebar,
                        showsSidebarToggle: true,
                        sidebarIsDocked:
                            navigation.regularSidebarIsDocked,
                        utilityPresentation:
                            navigation.utilityPresentation
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            navigation.handleRegularSidebarInteraction()
                        }
                    )
                    // Never zero: this rides over the rows, and a drag that
                    // begins on touch-down takes the press the reorder lift
                    // needs.
                    .simultaneousGesture(
                        DragGesture(
                            minimumDistance: MobileBrowserChromeLayout
                                .transientSidebarKeepAliveDistance
                        ).onChanged { _ in
                            navigation.handleRegularSidebarInteraction()
                        }
                    ),
                    detail: regularPageSurface(
                        adjoinsLeadingSidebar:
                            navigation.regularSidebarIsDocked
                            && layout.reservesSidebarWidth
                    )
                )
                .overlay {
                    MobileRegularUtilityFanLayer(
                        layout: layout,
                        layoutDirection: layoutDirection,
                        triggerFrameInGlobal: navigation.utilityPresentation
                            .triggerFrameInGlobal,
                        sidebarIsPresented:
                            navigation.regularSidebarIsPresented,
                        isExpanded: navigation.utilityPresentation
                            .isSwitcherExpanded,
                        selectedSurface: navigation.utilityPresentation.surface,
                        badgeColor: browser.selectedSpace?.branding.colors.first?
                            .color ?? .accentColor,
                        downloads: model.selectedUtilityDownloads,
                        newDownloadCount: model.newUtilityDownloads.count,
                        select: navigation.utilityPresentation.present
                    )
                }
            },
            palette: MobileBrowserCommandPaletteLayer(
                mode: commandPaletteMode,
                space: browser.selectedSpace,
                selectedTabID: browser.selectedTab?.id,
                otherSpaces: model.paletteOtherSpaces,
                commands: mobileBrowserCommandContext.paletteRegistry,
                isSourceAvailable: model.isPaletteSourceAvailable,
                selectTab: model.selectPaletteTab,
                selectTabInSpace: model.selectPaletteTab,
                openURL: { source, url, mode in
                    model.openPaletteURL(url, mode: mode, from: source)
                },
                dismiss: dismissCommandPalette,
                morphNamespace: compactChromeNamespace
            )
        )
        .focusedSceneValue(
            \.mobileBrowserCommandContext,
            mobileBrowserCommandContext
        )
        .sheet(item: $historyAssignment) { assignment in
            MobileHistoryView(
                browser: browser,
                assignment: assignment,
                spaceAccess: spaceAccess,
                openURL: openURL
            )
        }
        .modifier(
            MobileDownloadRiskConfirmationModifier(
                confirmation: pages.downloadRiskConfirmation
            )
        )
        .onChange(of: pages.urlCopyFeedbackRevision) { _, revision in
            presentURLCopyFeedback(revision: revision)
        }
        .onChange(of: pages.pageZoomFeedbackRevision) { _, revision in
            presentPageZoomFeedback(revision: revision)
        }
        .modifier(
            MobileBrowserRootLifecycleModifier(
                model: model,
                presentation: presentation,
                isAddressEditing: $isAddressEditing,
                storedSidebarWidth: $storedRegularSidebarWidth
            )
        )
        .onChange(of: browser.sidebarReorderState.isDragging, initial: true) {
            _, isDragging in
            navigation.setTransientSidebarDismissalPaused(isDragging)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            availableRootSize = size
        }
        .ignoresSafeArea(
            .keyboard,
            edges: ignoresFloatingKeyboardSafeArea ? .bottom : []
        )
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )
        ) { notification in
            keyboardEndFrame =
                notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect ?? .null
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            keyboardEndFrame = .null
        }
    }
}
