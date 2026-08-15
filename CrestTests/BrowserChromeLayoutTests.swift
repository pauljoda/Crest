import AppKit
import SwiftUI
import XCTest

@testable import Crest

final class BrowserChromeLayoutTests: XCTestCase {
    @MainActor
    func testCopyFeedbackRevisionAdvancesForEveryCopy() {
        let chrome = BrowserChromeState()

        chrome.showURLCopiedFeedback()
        chrome.showURLCopiedFeedback()

        XCTAssertEqual(chrome.urlCopyFeedbackRevision, 2)
    }

    @MainActor
    func testZoomFeedbackPublishesTheCurrentPercentage() {
        let chrome = BrowserChromeState()

        chrome.showPageZoomFeedback("110%")
        chrome.showPageZoomFeedback("125%")

        XCTAssertEqual(chrome.pageZoomFeedbackRevision, 2)
        XCTAssertEqual(chrome.pageZoomFeedbackLabel, "125%")
    }

    func testAddressControlBelongsToTheSpaceSidebar() {
        XCTAssertEqual(BrowserChromeLayout.addressPlacement, .spaceSidebar)
        XCTAssertFalse(BrowserChromeLayout.addressUsesCustomGlass)
        XCTAssertEqual(
            BrowserChromeLayout.addressSurfaceOpacity,
            CrestOpacity.chromeSurface
        )
        XCTAssertFalse(BrowserChromeLayout.addressEditingRingUsesAccent)
        XCTAssertEqual(BrowserChromeLayout.addressEditingRingWidth, 0.5)
    }

    func testNavigationControlsBelongToTheSpaceSidebar() {
        XCTAssertEqual(BrowserChromeLayout.navigationPlacement, .spaceSidebar)
    }

    func testArcStyleChromeMovesWithTheSidebar() {
        XCTAssertTrue(BrowserChromeLayout.windowControlsMoveWithSidebar)
        XCTAssertTrue(BrowserChromeLayout.usesSystemWindowControls)
        XCTAssertTrue(BrowserChromeLayout.preservesSystemWindowControlFrames)
        XCTAssertTrue(BrowserChromeLayout.usesSystemToolbarTitlebarMetrics)
        XCTAssertEqual(
            BrowserChromeLayout.sidebarNavigationControlOrder,
            [.back, .forward]
        )
        XCTAssertEqual(BrowserChromeLayout.sidebarTitlebarHeight, 48)
        XCTAssertEqual(BrowserChromeLayout.windowControlsReservedWidth, 67)
        XCTAssertEqual(
            BrowserChromeLayout.sidebarToggleLeadingInset,
            CrestSpacing.medium
        )
        XCTAssertEqual(
            BrowserChromeLayout.sidebarNavigationTrailingInset,
            CrestSpacing.medium
        )
        XCTAssertEqual(BrowserChromeLayout.sidebarToggleSymbolOffsetY, 1)
        XCTAssertEqual(BrowserChromeLayout.sidebarNavigationControlHitTarget, 30)
        XCTAssertEqual(BrowserChromeLayout.sidebarNavigationSymbolPointSize, 15)
    }

    func testSavedTabsHeaderKeepsCollapsedContentDiscoverable() {
        XCTAssertTrue(
            BrowserSpaceHeaderIconPolicy.showsDisclosure(
                isSavedTabsExpanded: false
            )
        )
        XCTAssertFalse(
            BrowserSpaceHeaderIconPolicy.showsDisclosure(
                isSavedTabsExpanded: true
            )
        )
    }

    func testFolderRowsUseTheirFolderIconAsDisclosureAcrossPlatforms() {
        XCTAssertFalse(BrowserFolderRowPresentationPolicy.showsSeparateChevron)
        XCTAssertTrue(
            BrowserFolderRowPresentationPolicy.usesEntireRowForDisclosure
        )
        XCTAssertEqual(
            BrowserFolderRowPresentationPolicy.systemImage(isExpanded: false),
            "folder"
        )
        XCTAssertEqual(
            BrowserFolderRowPresentationPolicy.systemImage(isExpanded: true),
            "folder.fill"
        )
    }

    func testSidebarPinsIdentityChromeAboveClippedTabContentAcrossPlatforms() {
        XCTAssertEqual(
            BrowserSidebarScrollLayoutPolicy.region(for: .essentials),
            .fixed
        )
        XCTAssertEqual(
            BrowserSidebarScrollLayoutPolicy.region(for: .spaceIdentity),
            .fixed
        )
        XCTAssertEqual(
            BrowserSidebarScrollLayoutPolicy.region(for: .savedTabs),
            .scrollable
        )
        XCTAssertEqual(
            BrowserSidebarScrollLayoutPolicy.region(for: .currentTabs),
            .scrollable
        )
        XCTAssertTrue(BrowserSidebarScrollLayoutPolicy.clipsScrollableRegion)
        XCTAssertNil(
            BrowserSidebarScrollLayoutPolicy.fixedSpaceHeaderMaxHeight,
            "Pinned Space chrome must keep its intrinsic row height"
        )
    }

    func testMobileFolderRowHighlightsOnlyForATabDrop() {
        XCTAssertTrue(
            BrowserFolderRowPresentationPolicy.showsDropHighlight(
                isTargeted: true,
                isTabDragging: true
            )
        )
        XCTAssertFalse(
            BrowserFolderRowPresentationPolicy.showsDropHighlight(
                isTargeted: true,
                isTabDragging: false
            )
        )
        XCTAssertFalse(
            BrowserFolderRowPresentationPolicy.showsDropHighlight(
                isTargeted: false,
                isTabDragging: true
            )
        )
    }

    func testCollapsedFolderKeepsTheTabThatWasVisibleWhenItCollapsed() {
        let folderTabID = TabID()
        let otherTabID = TabID()
        var state = BrowserCollapsedFolderTabVisibilityState()

        state.expansionDidChange(
            isExpanded: false,
            selectedTabID: folderTabID,
            folderTabIDs: [folderTabID]
        )

        XCTAssertEqual(state.keptTabID, folderTabID)
        XCTAssertNotEqual(state.keptTabID, otherTabID)
    }

    func testCollapsingFolderFromAnotherTabHidesEveryFolderTab() {
        let folderTabID = TabID()
        let otherTabID = TabID()
        var state = BrowserCollapsedFolderTabVisibilityState()

        state.expansionDidChange(
            isExpanded: false,
            selectedTabID: folderTabID,
            folderTabIDs: [folderTabID]
        )
        state.expansionDidChange(
            isExpanded: true,
            selectedTabID: otherTabID,
            folderTabIDs: [folderTabID]
        )
        state.expansionDidChange(
            isExpanded: false,
            selectedTabID: otherTabID,
            folderTabIDs: [folderTabID]
        )

        XCTAssertNil(state.keptTabID)
    }

    func testUnloadingKeptCollapsedFolderTabHidesIt() {
        let folderTabID = TabID()
        var state = BrowserCollapsedFolderTabVisibilityState()

        state.expansionDidChange(
            isExpanded: false,
            selectedTabID: folderTabID,
            folderTabIDs: [folderTabID]
        )
        state.tabDidUnload(folderTabID)

        XCTAssertNil(state.keptTabID)
    }

    func testSidebarBackgroundOffersOnlyFocusedSpaceManagementActions() {
        XCTAssertEqual(
            BrowserSidebarBackgroundInteractionPolicy.actions,
            [.editSpace, .newSpace]
        )
        XCTAssertEqual(
            BrowserSidebarBackgroundAction.editSpace.title,
            "Edit Space…"
        )
        XCTAssertEqual(
            BrowserSidebarBackgroundAction.newSpace.title,
            "New Space…"
        )
        XCTAssertTrue(
            BrowserSidebarBackgroundInteractionPolicy.usesNativeWindowDragGesture
        )
        XCTAssertTrue(
            BrowserSidebarBackgroundInteractionPolicy.limitsInteractionToUnoccupiedRemainder
        )
    }

    @MainActor
    func testSettingsPresentationKeepsTheLatestDestinationAndSpace() {
        let presentation = BrowserSpaceSettingsPresentationState()
        let first = SpaceID()
        let second = SpaceID()
        let firstAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: first,
            profileID: UUID()
        )
        let secondAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: second,
            profileID: UUID()
        )

        presentation.present(assignment: firstAssignment)
        presentation.present(.extensions, assignment: secondAssignment)

        XCTAssertEqual(presentation.requestedSpaceID, second)
        XCTAssertEqual(presentation.requestedAssignment, secondAssignment)
        XCTAssertEqual(presentation.requestedDestination, .extensions)
        XCTAssertEqual(presentation.revision, 2)
    }

    @MainActor
    func testRepeatedSettingsPresentationStillPublishesANewRequest() {
        let presentation = BrowserSpaceSettingsPresentationState()
        let spaceID = SpaceID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: UUID()
        )

        presentation.present(.extensions, assignment: assignment)
        presentation.present(.extensions, assignment: assignment)

        XCTAssertEqual(presentation.requestedDestination, .extensions)
        XCTAssertEqual(presentation.requestedSpaceID, spaceID)
        XCTAssertEqual(presentation.revision, 2)
    }

    @MainActor
    func testSettingsPresentationRejectsAReplacementBrowsingProfile() throws {
        let browser = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let original = try XCTUnwrap(browser.selectedSpace)
        let presentation = BrowserSpaceSettingsPresentationState()
        presentation.present(
            assignment: BrowserSpaceRuntimeAssignment(space: original)
        )
        let replacement = BrowserSpace(
            id: original.id,
            profile: BrowsingProfile(),
            name: original.name,
            symbol: original.symbol,
            accent: original.accent,
            branding: original.branding,
            folders: original.folders,
            tabs: original.tabs,
            archivedTabs: original.archivedTabs,
            history: original.history,
            browsingPreferences: original.browsingPreferences,
            credentialPreferences: original.credentialPreferences,
            accessPolicy: original.accessPolicy,
            isSavedTabsExpanded: original.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: original.savedTabsExpansionModifiedAt,
            selectedTabID: original.selectedTabID
        )
        let index = try XCTUnwrap(
            browser.session.spaces.firstIndex { $0.id == original.id }
        )
        browser.session.spaces[index] = replacement

        XCTAssertNil(presentation.requestedSpaceID(in: browser))
    }

    @MainActor
    func testExtensionCommandSettingsPresentationTargetsShortcuts() throws {
        let presentation = BrowserSpaceSettingsPresentationState()
        let spaceID = SpaceID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: UUID()
        )
        let route = try XCTUnwrap(
            BrowserExtensionCommandSettingsRoute(
                url: URL(
                    string: "chrome://extensions/configureCommands?command=eimadpbcbfnmbkopoojfekhnkhdbieeh-addSite"
                )!
            )
        )

        presentation.presentExtensionCommandSettings(
            route,
            assignment: assignment
        )

        XCTAssertEqual(presentation.requestedDestination, .shortcuts)
        XCTAssertEqual(presentation.requestedSpaceID, spaceID)
        XCTAssertEqual(presentation.requestedExtensionCommand, route)
        XCTAssertEqual(presentation.revision, 1)
    }

    func testSiteControlStaysMountedForAnActiveSiteUntilAddressEditingBegins() {
        XCTAssertTrue(
            BrowserSiteControlPresentationPolicy.isVisible(
                isAddressEditing: false,
                hasActiveSite: true
            )
        )
        XCTAssertFalse(
            BrowserSiteControlPresentationPolicy.isVisible(
                isAddressEditing: true,
                hasActiveSite: true
            )
        )
        XCTAssertFalse(
            BrowserSiteControlPresentationPolicy.isVisible(
                isAddressEditing: false,
                hasActiveSite: false
            )
        )
    }

    func testSiteControlPopoverUsesCompactURLBarScale() {
        XCTAssertLessThanOrEqual(BrowserSiteControlLayoutPolicy.width, 300)
        XCTAssertLessThanOrEqual(BrowserSiteControlLayoutPolicy.quickActionHeight, 36)
        XCTAssertLessThanOrEqual(BrowserSiteControlLayoutPolicy.quickActionGlyphSize, 14)
        XCTAssertLessThanOrEqual(BrowserSiteControlLayoutPolicy.extensionActionHeight, 36)
        XCTAssertLessThanOrEqual(BrowserSiteControlLayoutPolicy.extensionGlyphSize, 18)
    }

    func testPinnedExtensionsStayInOneCompactRowRegardlessOfCount() {
        XCTAssertLessThanOrEqual(
            BrowserPinnedExtensionStripLayoutPolicy.tileSize,
            24
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.sectionHeight,
            32
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.sectionCornerRadius,
            BrowserChromeLayout.addressCornerRadius
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.adjacentSpacing,
            CrestSpacing.small
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.addressBottomInset(
                hasPinnedExtensions: true
            ),
            CrestSpacing.small
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.addressBottomInset(
                hasPinnedExtensions: false
            ),
            BrowserSidebarMetrics.addressBottomInset
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.pinnedTabsTopInset(
                hasPinnedExtensions: true
            ),
            0
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.pinnedTabsTopInset(
                hasPinnedExtensions: false
            ),
            CrestSpacing.small
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.height(for: 0),
            0
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.height(for: 1),
            BrowserPinnedExtensionStripLayoutPolicy.sectionHeight
        )
        XCTAssertEqual(
            BrowserPinnedExtensionStripLayoutPolicy.height(for: 12),
            BrowserPinnedExtensionStripLayoutPolicy.sectionHeight
        )
    }

    func testPinnedExtensionPopupAnchorClearsTheInvokingIcon() {
        let interactionPoint = CGPoint(x: 112, y: 700)
        let popupAnchor =
            BrowserPinnedExtensionStripLayoutPolicy.popupAnchor(
                below: interactionPoint
            )

        XCTAssertEqual(popupAnchor.x, interactionPoint.x, accuracy: 0.001)
        XCTAssertEqual(
            popupAnchor.y,
            interactionPoint.y
                - BrowserPinnedExtensionStripLayoutPolicy.tileSize / 2
                - BrowserPinnedExtensionStripLayoutPolicy.popupGap,
            accuracy: 0.001
        )
    }

    func testChromeExtensionCommandURLRoutesToCrestShortcuts() throws {
        let route = try XCTUnwrap(
            BrowserExtensionCommandSettingsRoute(
                url: URL(
                    string: "chrome://extensions/configureCommands?command=eimadpbcbfnmbkopoojfekhnkhdbieeh-addSite"
                )!
            )
        )

        XCTAssertEqual(
            route.extensionID,
            "eimadpbcbfnmbkopoojfekhnkhdbieeh"
        )
        XCTAssertEqual(route.commandID, "addSite")
        XCTAssertNil(
            BrowserExtensionCommandSettingsRoute(
                url: URL(string: "https://example.com/extensions")!
            )
        )
    }

    func testWebExtensionShortcutKeysUseWebKitsSupportedCharacters() {
        XCTAssertEqual(
            BrowserExtensionShortcutPolicy.activationKey(
                for: .character("a")
            ),
            "a"
        )
        XCTAssertEqual(
            BrowserExtensionShortcutPolicy.activationKey(
                for: .special(.leftArrow)
            ),
            "\u{F702}"
        )
        XCTAssertNil(
            BrowserExtensionShortcutPolicy.activationKey(
                for: .special(.escape)
            )
        )
    }

    func testCertificateReviewRequiresHTTPSAndServerTrust() {
        XCTAssertTrue(
            BrowserSiteCertificatePresentationPolicy.isAvailable(
                url: URL(string: "https://example.com"),
                hasServerTrust: true
            )
        )
        XCTAssertFalse(
            BrowserSiteCertificatePresentationPolicy.isAvailable(
                url: URL(string: "http://example.com"),
                hasServerTrust: true
            )
        )
        XCTAssertFalse(
            BrowserSiteCertificatePresentationPolicy.isAvailable(
                url: URL(string: "https://example.com"),
                hasServerTrust: false
            )
        )
    }

    func testAddressBarSecurityAndSiteControlsStaySymmetric() {
        XCTAssertEqual(
            BrowserAddressSecurityControlPolicy.controlSize,
            BrowserTabTrailingControlPolicy.minimumHitTarget
        )
        XCTAssertTrue(
            BrowserAddressSecurityControlPolicy.isVisible(
                isAddressEditing: false,
                hasActiveSite: true
            )
        )
        XCTAssertFalse(
            BrowserAddressSecurityControlPolicy.isVisible(
                isAddressEditing: true,
                hasActiveSite: true
            )
        )
    }

    func testUnloadedAddressSummaryOmitsSearchGlyphToRemainCentered() {
        XCTAssertFalse(
            BrowserAddressLeadingControlPolicy.showsPlaceholderGlyph(
                isAddressEditing: false,
                hasActiveSite: false,
                hasAddress: true,
                hasResidentPage: false
            )
        )
        XCTAssertTrue(
            BrowserAddressLeadingControlPolicy.showsPlaceholderGlyph(
                isAddressEditing: false,
                hasActiveSite: false,
                hasAddress: false,
                hasResidentPage: false
            )
        )
        XCTAssertTrue(
            BrowserAddressLeadingControlPolicy.showsPlaceholderGlyph(
                isAddressEditing: true,
                hasActiveSite: false,
                hasAddress: true,
                hasResidentPage: false
            )
        )
    }

    func testExtensionPopupAnchorsAtTheInvokingControlWithTopLeadingFallback() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)

        XCTAssertEqual(
            BrowserExtensionPopupAnchorPolicy.anchorRect(
                in: bounds,
                interactionPoint: CGPoint(x: 176, y: 742)
            ).midX,
            176,
            accuracy: 0.001
        )
        let fallback = BrowserExtensionPopupAnchorPolicy.anchorRect(
            in: bounds,
            interactionPoint: CGPoint(x: 2_000, y: 2_000)
        )
        XCTAssertLessThan(fallback.midX, bounds.midX)
        XCTAssertGreaterThan(fallback.midY, bounds.midY)
    }

    @MainActor
    func testExtensionPopupKeepsTheInvokingBrowserWindowAfterFocusChanges() {
        let browserWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let transientWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 292, height: 420),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let anchor = BrowserExtensionPopupAnchor(
            screenPoint: CGPoint(x: 176, y: 742),
            sourceWindow: browserWindow
        )

        XCTAssertTrue(
            anchor.contentView(fallbackWindow: transientWindow)
                === browserWindow.contentView
        )
    }

    @MainActor
    func testExtensionPopupStaysBoundToTheInvokingViewAfterWindowMoves()
        throws
    {
        let browserWindow = NSWindow(
            contentRect: CGRect(x: 40, y: 80, width: 1_200, height: 800),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let iconView = NSView(
            frame: CGRect(x: 72, y: 710, width: 24, height: 24)
        )
        browserWindow.contentView?.addSubview(iconView)
        let anchor = BrowserExtensionPopupAnchor(sourceView: iconView)
            .offsetBy(dy: -18)

        browserWindow.setFrameOrigin(CGPoint(x: 320, y: 140))

        let source = try XCTUnwrap(
            anchor.presentationSource(fallbackWindow: nil)
        )
        XCTAssertTrue(source.view === iconView)
        XCTAssertEqual(source.rect, iconView.bounds)
    }

    func testSitePermissionsStartCollapsedInTheCompactFlyout() {
        XCTAssertFalse(BrowserSitePermissionDisclosurePolicy.defaultIsExpanded)
    }

    func testExpandedSitePermissionsExposeEveryPermissionControl() {
        XCTAssertTrue(
            BrowserSitePermissionDisclosurePolicy.visiblePermissions(
                isExpanded: false
            ).isEmpty
        )
        XCTAssertEqual(
            BrowserSitePermissionDisclosurePolicy.visiblePermissions(
                isExpanded: true
            ),
            BrowserSitePermission.allCases
        )
    }

    func testExpandedSitePermissionsGrowTheFlyoutViewport() {
        XCTAssertNil(
            BrowserSiteControlLayoutPolicy.height(
                permissionsExpanded: false
            )
        )
        XCTAssertEqual(
            BrowserSiteControlLayoutPolicy.height(
                permissionsExpanded: true
            ),
            520
        )
    }

    func testSidebarClearHistoryKeepsTheInitiatingSpaceAfterSelectionChanges() throws {
        var session = BrowserSession.preview
        let initiatingSpace = try XCTUnwrap(session.selectedSpace)
        let laterSelectedSpace = try XCTUnwrap(
            session.spaces.first { $0.id != initiatingSpace.id }
        )
        let clearHistory = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.name
        )

        session.selectSpace(laterSelectedSpace.id)

        XCTAssertEqual(session.selectedSpaceID, laterSelectedSpace.id)
        XCTAssertEqual(clearHistory.spaceID, initiatingSpace.id)
        XCTAssertEqual(clearHistory.spaceName, initiatingSpace.name)
    }

    func testWindowToolbarDoesNotReserveASeparateContentStrip() {
        XCTAssertFalse(BrowserChromeLayout.hidesWindowToolbar)
        XCTAssertFalse(BrowserChromeLayout.showsWindowToolbarBackground)
        XCTAssertTrue(BrowserChromeLayout.pageExtendsUnderTitlebar)
    }

    func testWindowControlsKeepNativeAppearanceAndBehavior() {
        XCTAssertTrue(BrowserChromeLayout.usesSystemWindowControlColors)
        XCTAssertTrue(BrowserChromeLayout.usesSystemWindowControlActions)
    }

    func testReloadFeedbackAlwaysReturnsToItsRestingOrientation() {
        XCTAssertEqual(BrowserReloadFeedbackPolicy.restingRotation, 0)
        XCTAssertEqual(BrowserReloadFeedbackPolicy.pressedRotation, 90)
        XCTAssertEqual(BrowserReloadFeedbackPolicy.duration, .milliseconds(240))
        XCTAssertEqual(BrowserReloadFeedbackPolicy.phaseDuration, .milliseconds(120))
        XCTAssertTrue(BrowserReloadFeedbackPolicy.usesGeometricCentering)
        XCTAssertTrue(BrowserReloadFeedbackPolicy.usesSharedSwiftUISymbolGeometry)
        XCTAssertFalse(BrowserReloadFeedbackPolicy.usesPlatformHostedImageView)
        XCTAssertFalse(BrowserReloadFeedbackPolicy.usesManualOpticalOffset)
        XCTAssertEqual(BrowserReloadFeedbackPolicy.symbolPointSize, 14)
    }

    func testReloadFeedbackKeepsTheReloadSymbolUntilRotationCompletes() {
        XCTAssertEqual(
            BrowserReloadFeedbackPolicy.symbolName(
                isLoading: true,
                isPlayingFeedback: true
            ),
            "arrow.clockwise"
        )
        XCTAssertEqual(
            BrowserReloadFeedbackPolicy.symbolName(
                isLoading: true,
                isPlayingFeedback: false
            ),
            "xmark"
        )
        XCTAssertEqual(
            BrowserReloadFeedbackPolicy.symbolName(
                isLoading: false,
                isPlayingFeedback: false
            ),
            "arrow.clockwise"
        )
    }

    func testTabTrailingControlKeepsAFullHitTargetWithoutGrowingItsGlyph() {
        XCTAssertEqual(
            BrowserTabTrailingControlPolicy.minimumHitTarget,
            CrestLayout.minimumHitTarget
        )
        XCTAssertLessThan(
            BrowserTabTrailingControlPolicy.glyphSize,
            BrowserTabTrailingControlPolicy.minimumHitTarget
        )
        XCTAssertEqual(BrowserTabTrailingControlPolicy.glyphSize, 12)
        XCTAssertTrue(BrowserTabTrailingControlPolicy.claimsItsFullHitTarget)
        XCTAssertTrue(BrowserTabTrailingControlPolicy.isSeparatedFromActivationTarget)
        XCTAssertTrue(BrowserTabTrailingControlPolicy.usesSharedHoverSurface)
        XCTAssertTrue(BrowserTabTrailingControlPolicy.preservesSidebarRowHeight)
    }

    func testCommandPaletteShellUsesOnlyNativeLiquidGlassRendering() {
        XCTAssertTrue(BrowserCommandPaletteMaterialPolicy.usesNativeLiquidGlass)
        XCTAssertFalse(BrowserCommandPaletteMaterialPolicy.glassIsInteractive)
        XCTAssertTrue(BrowserCommandPaletteMaterialPolicy.rowsKeepCustomStyling)
        XCTAssertFalse(BrowserCommandPaletteMaterialPolicy.addsCustomBorder)
        XCTAssertFalse(BrowserCommandPaletteMaterialPolicy.addsCustomShadow)
        XCTAssertTrue(
            BrowserCommandPaletteMaterialPolicy.usesOpaqueReduceTransparencyFallback
        )
    }

    func testMainBrowserWindowUsesSystemManagedResizableSizingHints() {
        XCTAssertTrue(BrowserMainWindowSizingPolicy.permitsUserResizing)
        XCTAssertEqual(
            BrowserMainWindowSizingPolicy.minimumContentSize,
            CGSize(width: 900, height: 600)
        )
        XCTAssertEqual(
            BrowserMainWindowSizingPolicy.idealContentSize,
            CGSize(width: 1440, height: 900)
        )
    }

    func testCollapsedSidebarLeavesOnlyTheWindowBorderVisible() {
        let presentation = BrowserSidebarPresentationPolicy.presentation(
            columnVisibility: .detailOnly,
            isFloatingSidebarPresented: false
        )

        XCTAssertEqual(presentation, .collapsed)
        XCTAssertFalse(presentation.showsSidebar)
        XCTAssertFalse(presentation.showsWindowControls)
        XCTAssertFalse(presentation.reservesSidebarWidth)
    }

    func testEdgeHoverPresentsSidebarWithoutMovingPageContent() {
        let presentation = BrowserSidebarPresentationPolicy.presentation(
            columnVisibility: .detailOnly,
            isFloatingSidebarPresented: true
        )

        XCTAssertEqual(presentation, .floating)
        XCTAssertTrue(presentation.showsSidebar)
        XCTAssertTrue(presentation.showsWindowControls)
        XCTAssertFalse(presentation.reservesSidebarWidth)
    }

    func testFloatingSidebarUsesTheFullSpaceThemeAndItsSidebarButtonDocks() {
        XCTAssertEqual(BrowserFloatingSidebarThemePolicy.spaceThemeOpacity, 1)
        XCTAssertEqual(
            BrowserSidebarPresentation.floating.sidebarToggleAction,
            .dock
        )
        XCTAssertEqual(
            BrowserSidebarPresentation.docked.sidebarToggleAction,
            .hide
        )
    }

    func testDockedSidebarKeepsNativeWindowControlsAndLayoutWidth() {
        let presentation = BrowserSidebarPresentationPolicy.presentation(
            columnVisibility: .all,
            isFloatingSidebarPresented: true
        )

        XCTAssertEqual(presentation, .docked)
        XCTAssertTrue(presentation.showsSidebar)
        XCTAssertTrue(presentation.showsWindowControls)
        XCTAssertTrue(presentation.reservesSidebarWidth)
    }

    func testAddressControlUsesCompactArcAlignedMetrics() {
        XCTAssertEqual(BrowserChromeLayout.addressHeight, 36)
        XCTAssertEqual(BrowserChromeLayout.addressCornerRadius, CrestRadius.compact)
        XCTAssertEqual(
            BrowserChromeLayout.sidebarHorizontalInset,
            CrestSpacing.small
        )
    }

    func testPageSeamRevealsTheContinuousSpaceCanvas() {
        XCTAssertEqual(BrowserChromeLayout.pageBrandSeamWidth, 1.5)
        XCTAssertEqual(
            BrowserChromeLayout.pageContentCornerRadius,
            BrowserChromeLayout.pageCornerRadius - BrowserChromeLayout.pageBrandSeamWidth
        )
    }

    func testFreestandingPageFrameUsesOneLockedWidthOnEverySide() {
        let insets = BrowserChromeLayout.pageFrameInsets(
            adjoinsLeadingSidebar: false
        )

        XCTAssertEqual(insets.top, BrowserChromeLayout.pageFrameInset)
        XCTAssertEqual(
            insets.leading,
            BrowserChromeLayout.pageFrameInset
        )
        XCTAssertEqual(
            insets.bottom,
            BrowserChromeLayout.pageFrameInset
        )
        XCTAssertEqual(
            insets.trailing,
            BrowserChromeLayout.pageFrameInset
        )
    }

    func testDockedSidebarReplacesOnlyTheLeadingPageFrameEdge() {
        let insets = BrowserChromeLayout.pageFrameInsets(
            adjoinsLeadingSidebar: true
        )

        XCTAssertEqual(insets.top, BrowserChromeLayout.pageFrameInset)
        XCTAssertEqual(insets.leading, 0)
        XCTAssertEqual(insets.bottom, BrowserChromeLayout.pageFrameInset)
        XCTAssertEqual(insets.trailing, BrowserChromeLayout.pageFrameInset)
    }

    func testQuickWindowKeepsACompactReadableControlLayer() {
        XCTAssertLessThanOrEqual(BrowserQuickWindowLayout.defaultWidth, 800)
        XCTAssertLessThanOrEqual(BrowserQuickWindowLayout.defaultHeight, 560)
        XCTAssertGreaterThanOrEqual(
            BrowserQuickWindowLayout.controlHeight,
            BrowserQuickWindowLayout.minimumMacHitTarget
        )
        XCTAssertGreaterThanOrEqual(BrowserQuickWindowLayout.minimumWidth, 560)
        XCTAssertGreaterThanOrEqual(BrowserQuickWindowLayout.addressMinimumWidth, 220)
        XCTAssertEqual(BrowserQuickWindowLayout.toolbarHeight, 56)
        XCTAssertEqual(BrowserQuickWindowLayout.windowControlClearance, 92)
        XCTAssertEqual(
            BrowserQuickWindowLayout.toolbarVerticalPadding,
            BrowserQuickWindowLayout.horizontalPadding
        )
        XCTAssertGreaterThan(BrowserQuickWindowLayout.pageTopClearance, 0)
        XCTAssertEqual(BrowserQuickWindowLayout.sourceChipHorizontalPadding, 9)
        XCTAssertEqual(
            BrowserQuickWindowLayout.pageBrandSeamWidth,
            BrowserChromeLayout.pageBrandSeamWidth
        )
        XCTAssertEqual(
            BrowserQuickWindowLayout.pageCornerRadius,
            BrowserChromeLayout.pageCornerRadius
        )
    }

    func testQuickWindowUsesStaticSpaceAddressAndOpenChrome() {
        XCTAssertFalse(BrowserQuickWindowChromePolicy.rendersHistoryControls)
        XCTAssertFalse(BrowserQuickWindowChromePolicy.animatesWindowContent)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.showsSourceSpaceBeforeAddress)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.integratesChromeWithTitlebar)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.sourceSpaceIsInformational)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.destinationHasSpaceSelector)
        XCTAssertFalse(BrowserQuickWindowChromePolicy.usesDedicatedAddressSurface)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.showsSingleMenuIndicator)
        XCTAssertFalse(BrowserQuickWindowChromePolicy.addsCustomToolbarBackingMaterials)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.usesNativeSplitDestinationControl)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.hidesSystemSharedBackgrounds)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.usesSingleToolbarRow)
        XCTAssertFalse(BrowserQuickWindowChromePolicy.usesNativeToolbarPlacements)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.usesRootInlineTitlebarRow)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.embedsSourceSpaceInAddressField)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.reusesMainAddressSurface)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.usesRootSpaceAtmosphere)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.usesInsetLiftedPageSurface)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.inheritsWindowTransparencyPreference)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.addressFillsAvailableToolbarWidth)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.destinationUsesDedicatedPrimaryAction)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.destinationMenuIndicatorIsTrailing)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.destinationUsesCustomSpacePicker)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.destinationSpacePickerUsesSharedArtwork)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.alignsNativeWindowControlsToToolbar)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.openActionAlwaysEntersDestinationSpace)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.spacePickerSelectionPromotesDirectly)
        XCTAssertFalse(BrowserQuickWindowChromePolicy.openActionRequiresLoadedPage)
        XCTAssertTrue(BrowserQuickWindowChromePolicy.usesExactSceneDismissal)
        XCTAssertGreaterThanOrEqual(
            BrowserQuickWindowLayout.spacePickerWidth,
            BrowserQuickWindowLayout.addressMinimumWidth
        )
        XCTAssertGreaterThanOrEqual(
            BrowserQuickWindowLayout.spacePickerRowHeight,
            BrowserQuickWindowLayout.minimumMacHitTarget
        )
        XCTAssertGreaterThan(BrowserQuickWindowLayout.addressVerticalPadding, 0)
        XCTAssertGreaterThan(BrowserQuickWindowLayout.initialAddressFocusDelay, .zero)
        XCTAssertEqual(
            BrowserQuickWindowChromePolicy.destinationTitle(spaceName: "Personal"),
            "Open in Personal"
        )
    }

    @MainActor
    func testQuickWindowCanAdoptTheMainWindowUnifiedTitlebarMetrics() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.toolbar = NSToolbar(identifier: "crest.quick-window.test")
        window.toolbarStyle = .unifiedCompact

        let host = BrowserNativeWindowControlsHostView(frame: .zero)
        window.contentView?.addSubview(host)
        host.applyBrowserChrome()

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertEqual(
            try XCTUnwrap(window.toolbar).identifier,
            BrowserNativeWindowControlsPolicy.toolbarIdentifier
        )
        for type in BrowserNativeWindowControlsPolicy.buttonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            XCTAssertFalse(button.isHidden)
        }
        host.restoreWindowChrome()
    }

    func testEmbeddedPrivateLockKeepsTheOwningSpaceSwitcherAsTheOnlySelector() {
        XCTAssertTrue(BrowserSpaceAccessPresentation.standalone.showsSpaceMenu)
        XCTAssertFalse(BrowserSpaceAccessPresentation.contentOverlay.showsSpaceMenu)
    }

    func testDesktopSpaceSwitcherBuildsExactlyOneSegmentPerSpace() {
        let spaces = BrowserSession.preview.spaces

        XCTAssertTrue(BrowserSpaceSwitcherLayout.usesOneButtonPerSpace)
        XCTAssertEqual(
            BrowserSpaceSwitcherLayout.segmentIDs(for: spaces),
            spaces.map(\.id)
        )
        XCTAssertEqual(
            BrowserSpaceSwitcherLayout.segmentWidth,
            CrestSpaceIconPickerMetrics.segmentWidth
        )
        XCTAssertEqual(
            BrowserSpaceSwitcherLayout.segmentHeight,
            CrestSpaceIconPickerMetrics.segmentHeight
        )
        XCTAssertEqual(
            BrowserSpaceSwitcherLayout.cornerRadius,
            CrestSpaceIconPickerMetrics.cornerRadius
        )
    }

    func testDesktopSpaceSwitcherUsesArchiveAsTheSingleCommonListTrigger() {
        XCTAssertNil(BrowserSpaceSwitcherLayout.leadingUtility)
        XCTAssertEqual(BrowserSpaceSwitcherLayout.trailingUtility, .commonLists)
        XCTAssertFalse(BrowserSpaceSwitcherLayout.showsSpaceCreation)
    }

    func testEveryOnboardingStepFollowsTheSystemAppearance() {
        XCTAssertNil(
            BrowserOnboardingAppearancePolicy.colorSchemeOverride(
                isManualSetup: true
            )
        )
        XCTAssertNil(
            BrowserOnboardingAppearancePolicy.colorSchemeOverride(
                isManualSetup: false
            )
        )
    }

    @MainActor
    func testSpacePagerDisablesBackingHorizontalScroller() {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true

        BrowserSpacePagerPolicy.hideHorizontalScroller(in: scrollView)

        XCTAssertFalse(BrowserSpacePagerPolicy.showsScrollIndicators)
        XCTAssertEqual(BrowserSpacePagerPolicy.scrollIndicatorVisibility, .never)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }

    func testSpacePagerActivatesResidentWebContentWithoutWaitingForMotionToSettle() {
        XCTAssertFalse(
            BrowserSpaceContentSelectionPolicy.defersWebContentUntilPagerSettles
        )
        XCTAssertFalse(
            BrowserSpaceContentSelectionPolicy.rootObserverDefersSpaceChanges
        )
    }

    func testSpacePagerLocksWhileSidebarContentIsBeingDragged() {
        XCTAssertTrue(BrowserSpacePagerPolicy.locksDuringContentDrag)
        XCTAssertTrue(BrowserSpacePagerPolicy.recentersWhenContentDragEnds)
        XCTAssertTrue(
            BrowserSpacePagerPolicy.isScrollEnabled(
                spaceCount: 2,
                isInteractionLocked: false
            )
        )
        XCTAssertFalse(
            BrowserSpacePagerPolicy.isScrollEnabled(
                spaceCount: 2,
                isInteractionLocked: true
            )
        )
        XCTAssertFalse(
            BrowserSpacePagerPolicy.isScrollEnabled(
                spaceCount: 1,
                isInteractionLocked: false
            )
        )
        XCTAssertTrue(
            BrowserSpacePagerPolicy.shouldRecenter(
                wasInteractionLocked: false,
                isInteractionLocked: true
            )
        )
        XCTAssertTrue(
            BrowserSpacePagerPolicy.shouldRecenter(
                wasInteractionLocked: true,
                isInteractionLocked: false
            )
        )
        XCTAssertFalse(
            BrowserSpacePagerPolicy.shouldRecenter(
                wasInteractionLocked: false,
                isInteractionLocked: false
            )
        )
    }

    func testDelayedPagerRecenterCannotOverrideANewerSpaceSelection() {
        let workID = SpaceID(
            rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        )
        let personalID = SpaceID(
            rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        )
        let request = BrowserSpacePagerRecenterRequest(
            revision: 4,
            spaceID: workID
        )

        XCTAssertTrue(
            request.isCurrent(
                revision: 4,
                selectedSpaceID: workID,
                isInteractionLocked: false
            )
        )
        XCTAssertFalse(
            request.isCurrent(
                revision: 5,
                selectedSpaceID: workID,
                isInteractionLocked: false
            )
        )
        XCTAssertFalse(
            request.isCurrent(
                revision: 4,
                selectedSpaceID: personalID,
                isInteractionLocked: false
            )
        )
        XCTAssertFalse(
            request.isCurrent(
                revision: 4,
                selectedSpaceID: workID,
                isInteractionLocked: true
            )
        )
    }

    func testEveryPageUsesOneRootLevelFloatingSurface() {
        XCTAssertTrue(BrowserPageSurfacePolicy.usesRootElevation)
        XCTAssertTrue(BrowserPageSurfacePolicy.usesExplicitExteriorShadowPath)
        XCTAssertTrue(BrowserPageSurfacePolicy.usesSharedRootContentSurface)
        XCTAssertTrue(BrowserPageSurfacePolicy.rootSurfaceOwnsClippingAndSeam)
        XCTAssertTrue(BrowserPageSurfacePolicy.collapsedSidebarKeepsFreestandingFrame)
        XCTAssertTrue(BrowserPageSurfacePolicy.quickWindowReusesRootContentSurface)
        XCTAssertTrue(BrowserPageSurfacePolicy.rootOwnsSpaceAtmosphere)
        XCTAssertFalse(BrowserPageSurfacePolicy.pageSurfacePaintsSpaceAtmosphere)
        XCTAssertFalse(BrowserPageSurfacePolicy.embedsStartPageRecess)
        XCTAssertFalse(BrowserPageSurfacePolicy.showsUnloadedPlaceholder)
        XCTAssertTrue(BrowserPageSurfacePolicy.startPageUsesSpaceAtmosphere)
        XCTAssertTrue(BrowserPageSurfacePolicy.usesSingleContinuousRootMask)
        XCTAssertTrue(BrowserPageSurfacePolicy.startPageUsesTransparentInnerSurface)
        XCTAssertTrue(
            BrowserPageSurfacePolicy.usesTransparentInnerSurface(
                isStartPage: true,
                hasActivePage: false
            )
        )
        XCTAssertTrue(
            BrowserPageSurfacePolicy.usesTransparentInnerSurface(
                isStartPage: false,
                hasActivePage: false
            )
        )
        XCTAssertFalse(
            BrowserPageSurfacePolicy.usesTransparentInnerSurface(
                isStartPage: false,
                hasActivePage: true
            )
        )
        XCTAssertGreaterThan(BrowserPageSurfacePolicy.shadowOpacity, 0)
        XCTAssertGreaterThan(BrowserPageSurfacePolicy.shadowRadius, 0)
        XCTAssertGreaterThan(BrowserPageSurfacePolicy.shadowYOffset, 0)
        XCTAssertTrue(BrowserPageSurfacePolicy.usesNativeSwiftUIShadow)
        XCTAssertLessThan(BrowserPageSurfacePolicy.shadowRadius, 12)
        XCTAssertLessThan(
            BrowserPageSurfacePolicy.shadowOpacity,
            CrestOpacity.controlShadow
        )
        XCTAssertTrue(BrowserPageSurfacePolicy.usesCrispBoundaryStroke)
        XCTAssertTrue(BrowserPageSurfacePolicy.shadowUsesContinuousSurfacePath)
        XCTAssertTrue(BrowserPageSurfacePolicy.shadowExcludesSurfaceInterior)
        XCTAssertTrue(BrowserPageSurfacePolicy.shadowAllocatesExteriorDrawingOutset)
        XCTAssertGreaterThanOrEqual(
            BrowserPageSurfacePolicy.shadowDrawingOutset,
            BrowserPageSurfacePolicy.shadowRadius
                + abs(BrowserPageSurfacePolicy.shadowYOffset)
        )
        XCTAssertFalse(BrowserPageSurfacePolicy.boundaryStrokeUsesSemanticForeground)
        XCTAssertTrue(BrowserPageSurfacePolicy.boundaryStrokeUsesDarkNeutral)
        XCTAssertEqual(BrowserPageSurfacePolicy.boundaryStrokeWidth, 0.5)
        XCTAssertEqual(
            BrowserPageSurfacePolicy.boundaryStrokeOpacity,
            CrestOpacity.border
        )
    }

    func testStartupBehaviorDefaultsToWaitingForTabSelection() {
        let suiteName = "BrowserChromeLayoutTests.startup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .waitForTabSelection
        )

        defaults.set("showStartPage", forKey: BrowserStartupPreference.key)
        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .waitForTabSelection
        )

        defaults.set(
            BrowserStartupBehavior.lastActiveTab.rawValue,
            forKey: BrowserStartupPreference.key
        )
        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .lastActiveTab
        )

        defaults.set("invalid", forKey: BrowserStartupPreference.key)
        XCTAssertEqual(
            BrowserStartupPreference.behavior(defaults: defaults),
            .waitForTabSelection
        )

        XCTAssertFalse(BrowserStartupBehavior.waitForTabSelection.activatesRestoredTab)
        XCTAssertTrue(BrowserStartupBehavior.lastActiveTab.activatesRestoredTab)
    }

    func testSettingsUsesNativeResizableNavigationSplitView() {
        XCTAssertTrue(BrowserSettingsChromePolicy.usesNavigationSplitView)
        XCTAssertTrue(BrowserSettingsChromePolicy.usesResizableDesktopSplitView)
        XCTAssertTrue(BrowserSettingsChromePolicy.usesDedicatedResizableWindowScene)
        XCTAssertTrue(BrowserSettingsChromePolicy.permitsUserWindowResizing)
        XCTAssertEqual(
            BrowserSettingsChromePolicy.minimumContentSize,
            CGSize(width: 840, height: 610)
        )
        XCTAssertEqual(
            BrowserSettingsChromePolicy.defaultContentSize,
            CGSize(width: 900, height: 660)
        )
        XCTAssertEqual(BrowserSettingsChromePolicy.detailMinimumWidth, 600)
        XCTAssertTrue(BrowserSettingsChromePolicy.usesNativeSidebarToggle)
        XCTAssertFalse(BrowserSettingsChromePolicy.showsSelectionInWindowTitle)
        XCTAssertTrue(BrowserSettingsChromePolicy.showsStandardWindowControls)
        XCTAssertEqual(BrowserSettingsChromePolicy.toolbarHeight, 38)
    }

    func testSettingsVisualPolicyUsesCalmNativeHierarchy() {
        XCTAssertEqual(BrowserSettingsVisualPolicy.sidebarMinimumWidth, 224)
        XCTAssertEqual(BrowserSettingsVisualPolicy.sidebarIdealWidth, 236)
        XCTAssertEqual(BrowserSettingsVisualPolicy.sidebarMaximumWidth, 260)
        XCTAssertEqual(BrowserSettingsVisualPolicy.sidebarIconSize, 24)
        XCTAssertEqual(BrowserSettingsVisualPolicy.sidebarRowMinimumHeight, 34)
        XCTAssertFalse(BrowserSettingsVisualPolicy.showsSidebarSubtitles)
        XCTAssertTrue(BrowserSettingsVisualPolicy.usesConciseNavigationLabels)
        XCTAssertFalse(BrowserSettingsVisualPolicy.usesSidebarAtmosphere)
        XCTAssertTrue(BrowserSettingsVisualPolicy.usesNativeSearchFields)
        XCTAssertTrue(BrowserSettingsVisualPolicy.centersPageIdentity)
        XCTAssertFalse(BrowserSettingsVisualPolicy.usesMonochromePageIdentity)
        XCTAssertTrue(BrowserSettingsVisualPolicy.usesEditorialPageIdentity)
        XCTAssertTrue(BrowserSettingsVisualPolicy.usesBrandSelectionTint)
        XCTAssertTrue(BrowserSettingsVisualPolicy.reservesProminenceForPrimaryActions)
        XCTAssertTrue(BrowserSettingsVisualPolicy.hidesResolvedPrimaryActions)
        XCTAssertEqual(BrowserSettingsVisualPolicy.pageIconSize, 48)
        XCTAssertEqual(BrowserSettingsVisualPolicy.maximumReadableContentWidth, 700)
    }

    func testSpaceCustomizationUsesAFullHeightPreviewWithoutANestedSidebar() {
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.usesCompactSpacePicker)
        XCTAssertFalse(BrowserSpaceCustomizationVisualPolicy.usesNestedSpaceSidebar)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.showsPersistentBrandingPreview)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.separatesAppearanceFromDetails)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.progressivelyDisclosesFineTuning)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.usesAdaptiveToolbar)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.stacksPreviewBeforeClipping)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.integratesPageIdentityIntoToolbar)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.describesPreviewAsSimplified)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.mobileUsesSharedSidebarPreview)
        XCTAssertTrue(BrowserSpaceCustomizationVisualPolicy.mobilePlacesPreviewBeforeControls)
        XCTAssertFalse(BrowserSpaceCustomizationVisualPolicy.toolbarShowsExplanatorySubtitle)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.previewMinimumWidth, 240)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.previewIdealWidth, 260)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.previewMaximumWidth, 320)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.editorMinimumWidth, 360)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.wideEditorMinimumWidth, 621)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.sectionPickerWidth, 280)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.compactSpacePickerWidth, 150)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.compactSectionPickerWidth, 220)
        XCTAssertEqual(BrowserSpaceCustomizationVisualPolicy.wideIdentityWidth, 120)
    }

    @MainActor
    func testSettingsWindowSizingAllowsGrowthBeyondItsDefaultSize() {
        let window = NSWindow(
            contentRect: CGRect(
                origin: .zero,
                size: BrowserSettingsChromePolicy.defaultContentSize
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentMaxSize = BrowserSettingsChromePolicy.defaultContentSize

        BrowserSettingsWindowSizing.apply(to: window)

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(
            window.contentMinSize,
            BrowserSettingsChromePolicy.minimumContentSize
        )
        XCTAssertGreaterThan(window.contentMaxSize.width, 10_000)
        XCTAssertGreaterThan(window.contentMaxSize.height, 10_000)
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isEnabled, true)
    }

    @MainActor
    func testSettingsWindowSizingRestoresTheWindowNameAssistiveTechnologyReads() {
        let window = NSWindow(
            contentRect: CGRect(
                origin: .zero,
                size: BrowserSettingsChromePolicy.defaultContentSize
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.alphaValue = 0

        BrowserSettingsWindowSizing.apply(to: window)

        XCTAssertEqual(window.title, BrowserSettingsChromePolicy.windowTitle)
        XCTAssertEqual(
            window.accessibilityTitle(),
            BrowserSettingsChromePolicy.windowTitle
        )
        XCTAssertEqual(
            window.alphaValue,
            1,
            "A window that can be typed into is never left transparent, because the accessibility tree still reports it as frontmost."
        )
    }

    @MainActor
    func testWindowAccessibilityNamesAWindowThatDrawsItsOwnChrome() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        BrowserWindowAccessibility.pinTitle(
            BrowserOnboardingWindowActivation.windowTitle,
            on: window
        )

        XCTAssertTrue(
            window.styleMask.contains(.titled),
            "A borderless window carries no title, so it cannot be addressed by name."
        )
        XCTAssertEqual(window.title, "Crest Setup")
        XCTAssertEqual(window.accessibilityTitle(), "Crest Setup")
    }

    func testPeekUsesOneThemedSplitActionAcrossPlatformsAndSupportsDirectKeys() {
        XCTAssertTrue(BrowserPeekChromePolicy.placesControlsAboveCard)
        XCTAssertTrue(BrowserPeekChromePolicy.alignsControlsToTrailingEdge)
        XCTAssertEqual(
            BrowserPeekChromePolicy.closeControlWidth,
            BrowserPeekChromePolicy.openControlWidth
        )
        XCTAssertEqual(BrowserPeekChromePolicy.controlHeight, 48)
        XCTAssertEqual(BrowserPeekChromePolicy.openControlWidth, 206)
        XCTAssertEqual(BrowserPeekChromePolicy.destinationLeadingInset, 16)
        XCTAssertEqual(BrowserPeekChromePolicy.destinationControlWidth, 48)
        XCTAssertEqual(BrowserPeekChromePolicy.openInTitle, "Open In…")
        XCTAssertTrue(BrowserPeekChromePolicy.primaryActionOpensSelectedSpace)
        XCTAssertTrue(BrowserPeekChromePolicy.usesSpaceBackgroundTint)
        XCTAssertTrue(BrowserPeekChromePolicy.showsTrailingSpaceMenu)
        XCTAssertEqual(
            BrowserPeekChromePolicy.menuTitle(spaceName: "Work"),
            "Work"
        )
        XCTAssertFalse(
            BrowserPeekChromePolicy.menuTitle(spaceName: "Work")
                .localizedCaseInsensitiveContains("current")
        )
        XCTAssertEqual(
            BrowserPeekKeyboardPolicy.action(forKeyCode: 53, modifierFlags: []),
            .dismiss
        )
        XCTAssertNil(
            BrowserPeekKeyboardPolicy.action(forKeyCode: 36, modifierFlags: [])
        )
        XCTAssertNil(
            BrowserPeekKeyboardPolicy.action(forKeyCode: 76, modifierFlags: [])
        )
        XCTAssertNil(
            BrowserPeekKeyboardPolicy.action(
                forKeyCode: 36,
                modifierFlags: [.command]
            )
        )
    }

    func testPeekUsesAnUncappedEightyPercentDesktopCardAndSharedSpringEntrance() {
        XCTAssertEqual(BrowserTransientWindowGeometryPolicy.contentFraction, 0.8)
        XCTAssertEqual(
            BrowserTransientWindowGeometryPolicy.contentSize(
                in: CGSize(width: 2_000, height: 1_000)
            ),
            CGSize(width: 1_600, height: 800)
        )
        XCTAssertEqual(
            BrowserPeekPresentationPolicy.desktopWebContentFrame(
                in: CGSize(width: 2_000, height: 1_000),
                reservedLeadingWidth: 300,
                layoutDirection: .leftToRight
            ),
            CGRect(x: 300, y: 0, width: 1_700, height: 1_000)
        )
        XCTAssertEqual(
            BrowserPeekPresentationPolicy.desktopWebContentFrame(
                in: CGSize(width: 2_000, height: 1_000),
                reservedLeadingWidth: 300,
                layoutDirection: .rightToLeft
            ),
            CGRect(x: 0, y: 0, width: 1_700, height: 1_000)
        )
        XCTAssertEqual(
            BrowserTransientWindowGeometryPolicy.centeredContentFrame(
                in: CGRect(x: 300, y: 40, width: 1_700, height: 1_000)
            ),
            CGRect(x: 470, y: 140, width: 1_360, height: 800)
        )
        XCTAssertEqual(
            BrowserPeekPresentationPolicy.entranceAnimation,
            CrestMotion.peekEntrance
        )
        XCTAssertFalse(
            BrowserPeekPresentationPolicy.revealsInitialWebContent(
                committedNavigationCount: 0
            )
        )
        XCTAssertTrue(
            BrowserPeekPresentationPolicy.revealsInitialWebContent(
                committedNavigationCount: 1
            )
        )
    }

    @MainActor
    func testQuickWindowCentersWithinSourceWebContentInsteadOfDisplay() {
        let sourceWebContentFrame = CGRect(
            x: 300,
            y: 40,
            width: 1_700,
            height: 1_000
        )
        let displayVisibleFrame = CGRect(
            x: 0,
            y: 0,
            width: 2_560,
            height: 1_400
        )

        XCTAssertEqual(
            BrowserQuickWindowGeometryHostView.targetFrame(
                sourceWebContentFrame: sourceWebContentFrame,
                fallbackVisibleFrame: displayVisibleFrame
            ),
            CGRect(x: 470, y: 140, width: 1_360, height: 800)
        )
    }

    @MainActor
    func testBrowserChromeClipsItsThemeFrameToFullscreenWindowBounds() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let contentFrame = try XCTUnwrap(window.contentView?.superview)
        contentFrame.clipsToBounds = false
        XCTAssertFalse(contentFrame.clipsToBounds)

        let host = BrowserNativeWindowControlsHostView(frame: .zero)
        window.contentView?.addSubview(host)
        host.applyBrowserChrome()

        XCTAssertTrue(contentFrame.clipsToBounds)
        host.restoreWindowChrome()
        XCTAssertFalse(contentFrame.clipsToBounds)
    }

    func testBrowserChromeHidesItsOwnedToolbarInFullscreen() {
        XCTAssertTrue(
            BrowserNativeWindowControlsPolicy.showsToolbar(
                in: [.titled, .resizable]
            )
        )
        XCTAssertFalse(
            BrowserNativeWindowControlsPolicy.showsToolbar(
                in: [.titled, .resizable, .fullScreen]
            )
        )
    }

    func testPeekNormalizesItsSourceToTheWebViewClickPoint() {
        let source = BrowserPeekPresentationPolicy.sourcePresentation(
            touchPoint: CGPoint(x: 850, y: 200),
            in: CGSize(width: 1_700, height: 800),
            hasTopLeadingOrigin: true,
            label: "Documentation"
        )

        XCTAssertEqual(source?.normalizedTouchX, 0.5)
        XCTAssertEqual(source?.normalizedTouchY, 0.25)
        XCTAssertEqual(source?.normalizedWidth, 0)
        XCTAssertEqual(source?.normalizedHeight, 0)
        XCTAssertEqual(source?.label, "Documentation")
    }

    func testCommandPaletteResultAreaSizesToItsContentBeforeScrolling() {
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                tabCount: 0,
                includesPrimaryAction: false
            ),
            0
        )
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                tabCount: 0,
                includesPrimaryAction: true
            ),
            82
        )
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                tabCount: 5,
                includesPrimaryAction: false
            ),
            345
        )
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                tabCount: 8,
                includesPrimaryAction: true
            ),
            390
        )
        XCTAssertEqual(
            BrowserCommandPaletteLayout.resultAreaHeight(
                tabCount: 5,
                includesPrimaryAction: false,
                maximumHeight: 160
            ),
            160
        )
    }

    func testCommandPaletteOverlayFadesWithoutScalingItsBackdrop() {
        XCTAssertEqual(BrowserCommandPaletteOverlayTransitionState.hidden.opacity, 0)
        XCTAssertEqual(BrowserCommandPaletteOverlayTransitionState.presented.opacity, 1)
        XCTAssertEqual(BrowserCommandPaletteOverlayTransitionState.hidden.scale, 1)
        XCTAssertEqual(
            BrowserCommandPaletteOverlayTransitionState.hidden.scale,
            BrowserCommandPaletteOverlayTransitionState.presented.scale
        )
    }

    func testReducedTransparencyRemovesAtmosphereAndStrengthensCustomScrims() {
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.atmosphereOpacity(
                0.22,
                reduceTransparency: false
            ),
            0.22
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.atmosphereOpacity(
                0.22,
                reduceTransparency: true
            ),
            0
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.scrimOpacity(
                0.18,
                reduceTransparency: false
            ),
            0.18
        )
        XCTAssertGreaterThanOrEqual(
            BrowserVisualAccessibilityPolicy.scrimOpacity(
                0.18,
                reduceTransparency: true
            ),
            0.5
        )
    }

    func testReducedMotionRemovesCustomSpatialChromeEffects() {
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialScale(
                0.965,
                reduceMotion: false
            ),
            0.965
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialScale(
                0.965,
                reduceMotion: true
            ),
            1
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialOffset(
                24,
                reduceMotion: false
            ),
            24
        )
        XCTAssertEqual(
            BrowserVisualAccessibilityPolicy.spatialOffset(
                24,
                reduceMotion: true
            ),
            0
        )
    }

    func testReducedMotionDisablesAppAuthoredChromeAnimations() {
        XCTAssertNotNil(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.chrome,
                reduceMotion: false
            )
        )
        XCTAssertNil(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.chrome,
                reduceMotion: true
            )
        )
    }

    func testColoredChromeChoosesAReadableForegroundInEveryAppearance() {
        let backgrounds: [Color] = [
            .blue,
            .cyan,
            .indigo,
            .green,
            .orange,
            .pink,
            .purple,
            .red,
            .teal,
            .gray,
        ]

        for colorScheme in [ColorScheme.light, .dark] {
            for background in backgrounds {
                let foreground = BrowserVisualAccessibilityPolicy.readableForeground(
                    over: background,
                    colorScheme: colorScheme
                )
                let ratio = BrowserVisualAccessibilityPolicy.contrastRatio(
                    foreground: foreground,
                    background: background,
                    colorScheme: colorScheme
                )

                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "\(background) must remain readable in \(colorScheme)."
                )
            }
        }
    }

    func testTabCloseControlUsesPrimaryTextInsteadOfTheSpaceTint() {
        for colorScheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = colorScheme
            let actual = BrowserVisualAccessibilityPolicy.tabCloseForeground
                .resolve(in: environment)
            let expected = Color.primary.resolve(in: environment)

            XCTAssertEqual(actual.linearRed, expected.linearRed, accuracy: 0.001)
            XCTAssertEqual(actual.linearGreen, expected.linearGreen, accuracy: 0.001)
            XCTAssertEqual(actual.linearBlue, expected.linearBlue, accuracy: 0.001)
            XCTAssertEqual(actual.opacity, expected.opacity, accuracy: 0.001)
        }
    }

    func testSpaceAccessibilityReportsPositionAndMovesOnlyOneSpace() throws {
        let session = BrowserSession.preview
        let work = try XCTUnwrap(session.spaces.first)
        let personal = try XCTUnwrap(session.spaces.last)

        XCTAssertEqual(
            BrowserChromeAccessibility.spaceValue(
                spaces: session.spaces,
                selectedSpaceID: work.id
            ),
            "Work, 1 of 2"
        )
        XCTAssertNil(
            BrowserChromeAccessibility.adjacentSpaceID(
                spaces: session.spaces,
                selectedSpaceID: work.id,
                direction: .previous
            )
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.adjacentSpaceID(
                spaces: session.spaces,
                selectedSpaceID: work.id,
                direction: .next
            ),
            personal.id
        )
    }

    func testChromeAccessibilityValuesPreserveTabFolderAndBadgeState() {
        XCTAssertEqual(
            BrowserChromeAccessibility.tabValue(isLoaded: true),
            "Loaded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.tabValue(isLoaded: false),
            "Not loaded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.folderValue(isExpanded: true),
            "Expanded"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.folderValue(isExpanded: false),
            "Collapsed"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.countValue(
                1,
                singular: "download",
                plural: "downloads"
            ),
            "1 download"
        )
        XCTAssertEqual(
            BrowserChromeAccessibility.countValue(
                2,
                singular: "archived tab",
                plural: "archived tabs"
            ),
            "2 archived tabs"
        )
    }

    func testSidebarResizeKeepsIntermediateWidthsInMemoryUntilCommit() {
        var transaction = BrowserSidebarWidthTransaction(persistedWidth: 289)

        transaction.resize(to: 302)
        transaction.resize(to: 318)
        transaction.resize(to: 341)

        XCTAssertEqual(transaction.width, 341)
        XCTAssertEqual(transaction.persistedWidth, 289)
        XCTAssertEqual(transaction.commit(), 341)
        XCTAssertEqual(transaction.persistedWidth, 341)
        XCTAssertNil(transaction.commit())
    }

    func testSidebarResizeClampsLiveAndRestoredWidths() {
        var transaction = BrowserSidebarWidthTransaction(persistedWidth: 120)

        XCTAssertEqual(transaction.width, BrowserChromeLayout.sidebarMinimumWidth)
        XCTAssertEqual(transaction.persistedWidth, BrowserChromeLayout.sidebarMinimumWidth)

        transaction.resize(to: 800)

        XCTAssertEqual(transaction.width, BrowserChromeLayout.sidebarMaximumWidth)
        XCTAssertEqual(transaction.commit(), BrowserChromeLayout.sidebarMaximumWidth)

        transaction.restore(persistedWidth: 300)

        XCTAssertEqual(transaction.width, 300)
        XCTAssertEqual(transaction.persistedWidth, 300)
    }

    func testSemanticLeadingGeometryMirrorsInRightToLeftLayouts() {
        XCTAssertEqual(
            BrowserChromeDirectionPolicy.leadingOffset(
                281,
                layoutDirection: .leftToRight
            ),
            281
        )
        XCTAssertEqual(
            BrowserChromeDirectionPolicy.leadingOffset(
                281,
                layoutDirection: .rightToLeft
            ),
            -281
        )
        XCTAssertEqual(
            BrowserChromeDirectionPolicy.sidebarResizeDelta(
                24,
                layoutDirection: .leftToRight
            ),
            24
        )
        XCTAssertEqual(
            BrowserChromeDirectionPolicy.sidebarResizeDelta(
                24,
                layoutDirection: .rightToLeft
            ),
            -24
        )
    }

    func testLeadingEdgeRevealGestureMovesInwardInEitherLayoutDirection() {
        XCTAssertTrue(
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                CGSize(width: 52, height: 8),
                layoutDirection: .leftToRight
            )
        )
        XCTAssertTrue(
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                CGSize(width: -52, height: 8),
                layoutDirection: .rightToLeft
            )
        )
        XCTAssertFalse(
            BrowserChromeDirectionPolicy.isLeadingEdgeReveal(
                CGSize(width: 52, height: 8),
                layoutDirection: .rightToLeft
            )
        )
    }

    /// The shared direction source for the compact toolbar's horizontal swipe.
    ///
    /// What that swipe *does* is no longer this policy's business — on iOS it
    /// pages Split View cards, routed by `MobileToolbarSwipePolicy` — but "next"
    /// still has to mean the trailing neighbour in both writing directions, and
    /// this is the only place that decides it.
    func testHorizontalToolbarSwipeSemanticsMirrorInRightToLeftLayouts() {
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(
                for: CGSize(width: -90, height: 12),
                layoutDirection: .leftToRight
            ),
            .next
        )
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(
                for: CGSize(width: 90, height: 12),
                layoutDirection: .rightToLeft
            ),
            .next
        )
    }

    func testSidebarAuxiliaryMouseButtonsSwitchSpacesWithoutClaimingOtherButtons() {
        XCTAssertEqual(
            BrowserSidebarMouseButtonPolicy.action(for: 3),
            .previousSpace
        )
        XCTAssertEqual(
            BrowserSidebarMouseButtonPolicy.action(for: 4),
            .nextSpace
        )
        XCTAssertNil(BrowserSidebarMouseButtonPolicy.action(for: 0))
        XCTAssertNil(BrowserSidebarMouseButtonPolicy.action(for: 2))
    }

    func testAuxiliaryMouseButtonsPreferAvailablePageHistoryUnderWebContent() {
        XCTAssertTrue(
            BrowserSidebarMouseButtonPolicy.routesToPage(
                isOverWebView: true,
                canNavigatePage: true
            )
        )
        XCTAssertFalse(
            BrowserSidebarMouseButtonPolicy.routesToPage(
                isOverWebView: true,
                canNavigatePage: false
            )
        )
        XCTAssertFalse(
            BrowserSidebarMouseButtonPolicy.routesToPage(
                isOverWebView: false,
                canNavigatePage: true
            )
        )
    }

    @MainActor
    func testOpenLocationRevealsTheSidebarAndPresentsTheCommandSurface() {
        let chrome = BrowserChromeState()
        chrome.hideSidebar()

        chrome.openLocation("https://example.com")

        XCTAssertEqual(chrome.columnVisibility, .all)
        XCTAssertEqual(
            chrome.commandPaletteMode,
            .editLocation("https://example.com")
        )
    }

    @MainActor
    func testRepeatedOpenLocationRequestsReplaceThePaletteQuery() {
        let chrome = BrowserChromeState()

        chrome.openLocation("https://example.com")
        chrome.openLocation("https://webkit.org")

        XCTAssertEqual(
            chrome.commandPaletteMode,
            .editLocation("https://webkit.org")
        )
    }

    @MainActor
    func testArchiveAndDownloadsPresentationIsExclusiveToItsOwningWindow() {
        let firstWindow = BrowserChromeState()
        let secondWindow = BrowserChromeState()

        firstWindow.utilityPresentation.present(.downloads)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .downloads)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.present(.archive)

        XCTAssertEqual(firstWindow.utilityPresentation.surface, .archive)
        XCTAssertNil(secondWindow.utilityPresentation.surface)

        firstWindow.utilityPresentation.dismiss(.downloads)
        XCTAssertEqual(
            firstWindow.utilityPresentation.surface,
            .archive,
            "A stale popover dismissal must not close the replacement Archive surface."
        )

        firstWindow.utilityPresentation.dismiss(.archive)
        XCTAssertNil(firstWindow.utilityPresentation.surface)
    }

    func testDownloadsShortcutMatchesInstalledArcAndClick() {
        XCTAssertEqual(
            BrowserShortcutCommand.showDownloads.defaultShortcut,
            BrowserShortcut(
                key: .character("j"),
                modifiers: [.command, .shift]
            )
        )
    }

    func testStopLoadingShortcutMatchesInstalledArc() {
        XCTAssertEqual(
            BrowserShortcutCommand.stopLoading.defaultShortcut,
            BrowserShortcut(
                key: .character("."),
                modifiers: .command
            )
        )
    }

    @MainActor
    func testMacChromeRestoresItsOwningWindowsSidebarPresentation() {
        let hiddenChrome = BrowserChromeState(sidebarIsPresented: false)
        let visibleChrome = BrowserChromeState(sidebarIsPresented: true)

        XCTAssertEqual(hiddenChrome.columnVisibility, .detailOnly)
        XCTAssertEqual(visibleChrome.columnVisibility, .all)
    }

    func testSettingsControlsUseOneAccessibleInteractionVocabulary() {
        XCTAssertEqual(BrowserSettingsControlPolicy.minimumTouchTarget, 44)
        XCTAssertTrue(BrowserSettingsControlPolicy.labeledActionsShowBoundaries)
        XCTAssertTrue(BrowserSettingsControlPolicy.denseActionsKeepVisiblePressFeedback)
        XCTAssertFalse(BrowserSettingsControlPolicy.selectedCardsShowRedundantCheckmarks)
        XCTAssertTrue(BrowserSettingsControlPolicy.privacyShowsProtectionSummaryOnly)
    }

}
