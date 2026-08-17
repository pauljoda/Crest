import SwiftUI

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
                sidebar: MobileBrowserSidebarSurface(
                    browser: browser,
                    pages: pages,
                    dataDeleter: dataDeleter,
                    spaceAccess: spaceAccess,
                    mode: .compactTabViewer,
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
                    hideSidebar: {},
                    utilityPresentation: navigation.utilityPresentation
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
                        isStartPage: browser.selectedTab?.isStartPage == true,
                        hasSelectedPage: model.selectedPage != nil,
                        pageThemeColor: model.selectedPage?.themeColor,
                        underPageBackgroundColor:
                            model.selectedPage?.webView.underPageBackgroundColor,
                        space: browser.selectedSpace
                    ),
                    detail: MobileBrowserDetailSurface(
                        browser: browser,
                        pages: pages,
                        spaceAccess: spaceAccess,
                        address: model.addressBinding,
                        isAddressEditing: $isAddressEditing,
                        addressFocusRequest: addressFocusRequest,
                        isCommandPalettePresented: commandPaletteMode != nil,
                        isCompact: true,
                        showsCompactToolbar: true,
                        compactToolbarIsHidden:
                            navigation.compactToolbarIsHidden,
                        submitAddress: submitAddress,
                        beginNewTab: beginNewTab,
                        showTabViewer: showTabViewer,
                        hideCompactToolbar: navigation.hideCompactToolbar,
                        showCompactToolbar: navigation.showCompactToolbar,
                        handleToolbarSwipe: handleToolbarSwipe,
                        selectSplitCard: selectSplitCard,
                        compactTransitionEnded: finishCompactTransition
                    )
                )
            ),
            regular: { layout in
                MobileRegularBrowserLayout(
                    layout: layout,
                    sidebarIsPresented:
                        navigation.regularSidebarIsPresented,
                    isCommandPalettePresented: commandPaletteMode != nil,
                    sideBySide: { sidebarWidth in
                        MobileRegularSideBySideLayout(
                            sidebarWidth: sidebarWidth,
                            sidebarIsPresented:
                                navigation.regularSidebarIsPresented,
                            preferredSidebarWidth: model.sidebarWidthBinding,
                            reduceMotion: reduceMotion,
                            layoutDirection: layoutDirection,
                            showSidebar: showRegularSidebar,
                            commitSidebarWidth: commitRegularSidebarWidth,
                            sidebar: MobileBrowserSidebarSurface(
                                browser: browser,
                                pages: pages,
                                dataDeleter: dataDeleter,
                                spaceAccess: spaceAccess,
                                mode: .regularSidebar,
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
                                hideSidebar: hideRegularSidebar,
                                utilityPresentation:
                                    navigation.utilityPresentation
                            ),
                            detail: regularPageSurface(
                                adjoinsLeadingSidebar:
                                    navigation.regularSidebarIsPresented
                            )
                        )
                    },
                    overlay: { sidebarWidth in
                        MobileRegularOverlayLayout(
                            sidebarWidth: sidebarWidth,
                            sidebarIsPresented:
                                navigation.regularSidebarIsPresented,
                            reduceMotion: reduceMotion,
                            reduceTransparency: reduceTransparency,
                            layoutDirection: layoutDirection,
                            showSidebar: showRegularSidebar,
                            hideSidebar: hideRegularSidebar,
                            sidebar: MobileBrowserSidebarSurface(
                                browser: browser,
                                pages: pages,
                                dataDeleter: dataDeleter,
                                spaceAccess: spaceAccess,
                                mode: .regularSidebar,
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
                                hideSidebar: hideRegularSidebar,
                                utilityPresentation:
                                    navigation.utilityPresentation
                            ),
                            detail: regularPageSurface(
                                adjoinsLeadingSidebar: false
                            )
                        )
                    }
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
    }
}
