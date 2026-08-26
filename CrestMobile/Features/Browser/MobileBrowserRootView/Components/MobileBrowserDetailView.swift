import SwiftUI

struct MobileBrowserDetailView: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let isCommandPalettePresented: Bool
    let isCompact: Bool
    let obscuresSystemSafeAreas: Bool
    let showsCompactToolbar: Bool
    let compactToolbarIsHidden: Bool
    let handleWebContentInteraction: () -> Void
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    let showTabViewer: () -> Void
    let hideCompactToolbar: () -> Void
    let showCompactToolbar: () -> Void
    let handleToolbarSwipe: (BrowserSpaceSwipeDirection) -> Void
    let selectSplitCard: (TabID) -> Void
    let compactTransitionEnded: (CGSize) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    /// The page area's safe area, measured here because this is the last place
    /// both paths share it: the carousel's `ScrollView` resolves its cells'
    /// safe area to zero, so a cell can only learn the real one as data.
    @State private var resolvedSafeAreaInsets = EdgeInsets()
    @State private var downloadsAssignment: BrowserSpaceRuntimeAssignment?

    var body: some View {
        let pageActions = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages
        )
        let page = pageActions?.activePage
        let pagePresentation = pagePresentation(for: page)
        let viewport = pageViewport
        Group {
            if let splitCardSpace,
                let splitCardMembers,
                let focusedTabID = browser.selectedTab?.id
            {
                MobileSplitCardPager(
                    members: splitCardMembers,
                    space: splitCardSpace,
                    focusedTabID: focusedTabID,
                    pages: pages,
                    viewport: viewport,
                    selectTab: selectSplitCard,
                    prepareMember: prepareSplitCardPage,
                    handleInteraction: handleWebContentInteraction
                )
                .ignoresSafeArea(.container, edges: .vertical)
            } else {
                switch pagePresentation {
                case .noSelection, .unloaded:
                    unloadedPageSurface
                case .startPage:
                    if browser.selectedTab != nil {
                        BrowserStartPage(
                            space: browser.selectedSpace,
                            isPrivateBrowsing: browser.isPrivateBrowsing,
                            selectedTabID: browser.selectedSpace?.selectedTabID,
                            isSourceAvailable: isPaletteSourceAvailable,
                            selectTab: selectStartPageTab,
                            openURL: openStartPageURL,
                            isCommandPaletteObscured: isCommandPalettePresented,
                            layout: isCompact ? .mobileCompactPage : .mobileRegularPage,
                            focusRequest: addressFocusRequest,
                            headerColorScheme: startPageHeaderColorScheme
                        )
                        .onChange(of: isCompact, initial: true) { _, compact in
                            if compact { address = "" }
                        }
                    } else {
                        unloadedPageSurface
                    }
                case .livePage:
                    if let page {
                        MobileBrowserLivePageView(
                            page: page,
                            viewport: viewport,
                            handleInteraction: handleWebContentInteraction
                        )
                    } else {
                        unloadedPageSurface
                    }
                case .navigationFailure:
                    if let page, let failure = page.navigationFailure {
                        BrowserNavigationFailureView(
                            failure: failure,
                            branding: browser.selectedSpace?.branding,
                            layout: isCompact ? .compact : .regular,
                            canGoBack: page.canReturnFromNavigationFailure,
                            canProceed: page.canProceedAfterCertificateFailure,
                            retry: page.retryAfterNavigationFailure,
                            goBack: page.returnFromNavigationFailure,
                            proceed: page.proceedAfterCertificateFailure
                        )
                    } else {
                        unloadedPageSurface
                    }
                case .processFailure:
                    if let page {
                        BrowserNavigationFailureView(
                            failure: .webContentProcessStopped(url: page.displayURL),
                            branding: browser.selectedSpace?.branding,
                            layout: isCompact ? .compact : .regular,
                            canGoBack: false,
                            canProceed: false,
                            retry: page.retryAfterProcessFailure,
                            goBack: {},
                            proceed: {}
                        )
                    } else {
                        unloadedPageSurface
                    }
                case .automaticRestore:
                    unloadedPageSurface
                        .onAppear {
                            restoreSelectedTab()
                        }
                }
            }
        }
        .background(safeAreaProbe)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let page {
                BrowserCredentialChrome(
                    presentation: BrowserCredentialChromePresentation.resolve(
                        saveCandidate: page.credentialSaveCandidate,
                        fillRequest: page.credentialFillRequest
                    ),
                    fillPort: credentialFillPort(for: page),
                    savePort: credentialSavePort(for: page),
                    browser: browser,
                    capabilities: capabilities
                )
            }
        }
        .overlay(alignment: .bottom) {
            if isCompact, showsCompactToolbar {
                if browser.selectedTab?.isStartPage == true {
                    MobileCompactStartPageToolbar(showTabViewer: showTabViewer)
                        .safeAreaPadding(.bottom, 0)
                        .zIndex(1)
                } else if compactToolbarIsHidden {
                    MobileCompactDomainChip(
                        url: page?.url,
                        showToolbar: showCompactToolbar
                    )
                    .safeAreaPadding(.bottom, 0)
                    .zIndex(1)
                } else {
                    MobileCompactPageToolbar(
                        browser: browser,
                        pageActions: pageActions,
                        downloadsAccess: compactDownloadsAccess,
                        address: $address,
                        isAddressEditing: $isAddressEditing,
                        submitAddress: submitAddress,
                        beginNewTab: beginNewTab,
                        showTabViewer: showTabViewer,
                        hideToolbar: hideCompactToolbar,
                        handleSwipe: handleToolbarSwipe,
                        compactTransitionEnded: compactTransitionEnded
                    )
                    .safeAreaPadding(.bottom, 0)
                    .zIndex(1)
                }
            }
        }
        .overlay(alignment: isCompact ? .bottom : .topTrailing) {
            if let page, page.isFindPresented {
                BrowserFindBar(
                    port: findPort(for: page),
                    capabilities: capabilities,
                    isPageActive: true
                )
                .frame(
                    maxWidth: isCompact
                        ? .infinity
                        : MobileBrowserChromeLayout.regularFindMaximumWidth
                )
                .padding(
                    .horizontal,
                    isCompact
                        ? MobileBrowserChromeLayout.compactFindHorizontalPadding
                        : MobileBrowserChromeLayout.regularFindHorizontalPadding
                )
                .padding(
                    .top,
                    isCompact ? 0 : MobileBrowserChromeLayout.regularFindTopPadding
                )
                .padding(
                    .bottom,
                    isCompact && showsCompactToolbar
                        ? compactBottomChromeHeight
                            + MobileBrowserChromeLayout.compactFindToolbarGap
                        : MobileBrowserChromeLayout.findFallbackBottomPadding
                )
                .zIndex(2)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: isCompact ? .bottom : .top)
                            .combined(with: .opacity)
                )
            }
        }
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.toolbar,
                reduceMotion: reduceMotion
            ),
            value: page?.isFindPresented
        )
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.toolbar,
                reduceMotion: reduceMotion
            ),
            value: compactToolbarIsHidden
        )
        .sheet(item: $downloadsAssignment) { assignment in
            MobileDownloadsView(
                browser: browser,
                pages: pages,
                assignment: assignment,
                spaceAccess: spaceAccess
            )
        }
    }

    /// What the page area's safe area is, measured clear of the keyboard.
    ///
    /// The probe ignores the keyboard region deliberately. SwiftUI spells
    /// keyboard avoidance as a safe area, so a probe that read it would report
    /// the keyboard's height as page chrome, and `MobileBrowserWebHostView`
    /// would inset the page by it a second time — on top of the shortening
    /// SwiftUI has already done — leaving the page laid out in a fraction of
    /// the web view with a dead band beneath it. What the page owes the
    /// keyboard is already paid by the layout; what it owes the window is what
    /// this measures.
    private var safeAreaProbe: some View {
        Color.clear
            .onGeometryChange(for: EdgeInsets.self) { proxy in
                proxy.safeAreaInsets
            } action: { insets in
                resolvedSafeAreaInsets = insets
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .accessibilityHidden(true)
    }

    private var compactDownloadsAccess: MobileDownloadsMenuAccess? {
        guard isCompact,
            let selectedSpace = browser.selectedSpace,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: selectedSpace),
                in: browser,
                accessController: spaceAccess
            )
        else { return nil }
        let items = pages.downloadCenter.items(for: space.profile.id)
        return MobileDownloadsMenuAccess(
            newItemCount: pages.downloadCenter
                .unacknowledgedItems(for: space.profile.id).count,
            activeProgress: BrowserDownloadNotificationPolicy.progress(
                in: items
            ),
            open: presentCompactDownloads
        )
    }

    private func presentCompactDownloads() {
        guard let selectedSpace = browser.selectedSpace,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: selectedSpace),
                in: browser,
                accessController: spaceAccess
            )
        else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        _ = pages.downloadCenter.acknowledgeItems(for: space.profile.id)
        downloadsAssignment = assignment
    }

    /// The four questions the find bar asks, bound to the page it is over.
    private func findPort(for page: MobileBrowserPage) -> BrowserFindPort {
        BrowserFindPort(
            find: { query, direction in
                page.find(query, direction: direction)
            },
            query: { page.findQuery },
            matchState: { page.findMatchState },
            focusRequest: { page.findFocusRequest },
            dismiss: page.dismissFind
        )
    }

    /// The four things a credential fill prompt asks, bound to the page it is
    /// over.
    private func credentialFillPort(
        for page: MobileBrowserPage
    ) -> BrowserCredentialFillPort {
        BrowserCredentialFillPort(
            spaceID: page.spaceID,
            contentScale: page.pageZoom,
            siteIconData: page.faviconData,
            fill: { credential, requestID in
                try await page.fillCredential(credential, for: requestID)
            },
            fillGeneratedPassword: { password, requestID in
                try await page.fillGeneratedPassword(password, for: requestID)
            },
            dismiss: page.dismissCredentialFillRequest
        )
    }

    /// What the save prompt asks of the page it is over. This shell can hand a
    /// saved password on to the system's Passwords app, anchored on the window
    /// the page is living in at the moment the offer is made.
    private func credentialSavePort(
        for page: MobileBrowserPage
    ) -> BrowserCredentialSavePort {
        BrowserCredentialSavePort(
            spaceID: page.spaceID,
            presentedCandidateID: { page.credentialSaveCandidate?.id },
            dismiss: page.dismissCredentialSaveCandidate,
            offerToSystemPasswords: { candidate, title in
                try await BrowserSystemPasswordWriteThroughSystem.offer(
                    candidate: candidate,
                    title: title,
                    anchor: page.webView.window
                )
            }
        )
    }

    /// What this shell can do, as far as the find bar and the credential
    /// prompts are concerned: they are aimed at with a finger, whichever
    /// placement they are drawn in.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(supportsTouch: true)
    }

    /// The one viewport both paths render with.
    ///
    /// The selected tab on its own and every card of its group are handed this
    /// same value, which is what makes a grouped tab render exactly like the
    /// plain tab it is.
    private var pageViewport: MobileBrowserPageViewport {
        let safeAreaInsets = MobileBrowserViewportPolicy.systemSafeAreaInsets(
            resolvedSafeAreaInsets,
            layoutDirection: layoutDirection
        )
        return MobileBrowserPageViewport(
            obscuresSystemSafeAreas: obscuresSystemSafeAreas,
            systemSafeAreaInsets: safeAreaInsets,
            bottomChromeHeight: isCompact && showsCompactToolbar
                ? compactBottomChromeHeight
                : 0
        )
    }

    /// The Space whose cards the carousel may page, or `nil` for the single-page
    /// path.
    ///
    /// Compact only: iPad presents the very same members as real columns. A
    /// locked Space is excluded outright — the page store has already dropped
    /// every card, so a carousel there would page through empty placeholders of
    /// content the lock exists to put away.
    private var splitCardSpace: BrowserSpace? {
        guard isCompact,
            let space = browser.selectedSpace,
            !spaceAccess.isLocked(space)
        else { return nil }
        return space
    }

    /// The presented run when it is long enough to page, otherwise `nil`.
    private var splitCardMembers: [BrowserTab]? {
        guard let space = splitCardSpace else { return nil }
        let members = space.presentedSplitMembers(for: browser.selectedTab?.id)
        let isRenderableRun = MobileSplitCardPagerPolicy.isPagerPresented(
            memberCount: members.count
        )
        return isRenderableRun ? members : nil
    }

    /// Builds the page a carousel cell is about to show. Called as the cell
    /// materializes, so a group only ever holds the cards near the viewport.
    private func prepareSplitCardPage(_ tabID: TabID) {
        pages.prepareResidentPage(for: tabID, in: browser.session)
    }

    private func pagePresentation(
        for page: MobileBrowserPage?
    ) -> BrowserPagePresentation {
        BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: selectionPresentation,
                hasActivePage: page != nil,
                hasNavigationFailure: page?.navigationFailure != nil,
                hasProcessFailure: page?.showsProcessFailure == true,
                unloadedBehavior: isCompact
                    ? .restoreAutomatically
                    : .remainUnloaded
            )
        )
    }

    private var selectionPresentation: BrowserPagePresentationSelection {
        guard let tab = browser.selectedTab else { return .none }
        return tab.isStartPage ? .startPage : .webPage
    }

    /// The appearance the start page's header reads its text tone from.
    ///
    /// Touch draws that header over the Space's branding, so the text follows
    /// the branding rather than the system appearance. Without a Space there is
    /// no brand to follow and the header inherits the environment's appearance.
    private var startPageHeaderColorScheme: ColorScheme? {
        guard
            MobileStartPageAppearancePolicy.foregroundTone(
                usesCommandPalette: !isCompact
            ) == .onBrand,
            let space = browser.selectedSpace
        else { return nil }
        return BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
    }

    private var unloadedPageSurface: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var compactBottomChromeHeight: CGFloat {
        compactToolbarIsHidden
            ? MobileBrowserViewportPolicy.compactDomainChipHeight
            : MobileBrowserViewportPolicy.compactToolbarHeight
    }

    private func restoreSelectedTab() {
        pages.select(session: browser.session)
    }

    private func openStartPageURL(
        _ source: BrowserTabRuntimeAssignment,
        _ url: URL
    ) -> Bool {
        guard isPaletteSourceAvailable(source) else { return false }
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.contentNavigation,
                reduceMotion: reduceMotion
            )
        ) {
            browser.navigateSelectedTab(to: url)
            pages.select(session: browser.session)
            pages.load(url)
        }
        return true
    }

    private func selectStartPageTab(
        _ source: BrowserTabRuntimeAssignment,
        _ target: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            let destination = BrowserCommandPaletteActionPolicy.target(
                target,
                from: source,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        browser.selectSpace(destination.space.id)
        browser.selectTab(destination.tab.id)
        pages.select(session: browser.session)
        return true
    }

    private func isPaletteSourceAvailable(
        _ source: BrowserTabRuntimeAssignment
    ) -> Bool {
        BrowserCommandPaletteActionPolicy.isSourceAvailable(
            source,
            in: browser,
            accessController: spaceAccess
        )
    }
}
