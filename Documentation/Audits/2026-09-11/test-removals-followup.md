# Follow-up removal ledger

The user explicitly requested more aggressive cleanup for settled, low-risk behavior and accepted retirement of the remaining failing scenarios. The reasons below distinguish retained coverage from an accepted reduction in coverage; removed failures are not described as fixed.

## CrestTests/BrowserChromeLayoutTests.swift

Retire settled presentation/animation/value-policy snapshots under the stricter retention standard. Native host identity/document survival, popup anchoring, overflow/drag clipping, real command dispatch, initial-content visibility and accessibility input constraints remain in the owning chrome/page/quick-window suites. Exact appearance is no longer a permanent test contract.

- `testExtensionNewBadgeStaysOnOneLineAtToolbarSize`
- `testExtensionBadgesDoNotChangeArtworkLayoutSize`
- `testCopyFeedbackRevisionAdvancesForEveryCopy`
- `testZoomFeedbackPublishesTheCurrentPercentage`
- `testSavedTabsHeaderKeepsCollapsedContentDiscoverable`
- `testFolderRowsUseTheirFolderIconAsDisclosureAcrossPlatforms`
- `testSidebarPinsIdentityChromeAboveClippedTabContentAcrossPlatforms`
- `testSidebarBackgroundOffersOnlyFocusedSpaceManagementActions`
- `testPinnedExtensionsStayInOneCompactRowRegardlessOfCount`
- `testPinnedExtensionPopupAnchorClearsTheInvokingIcon`
- `testAddressBarSecurityAndSiteControlsStaySymmetric`
- `testUnloadedAddressSummaryOmitsSearchGlyphToRemainCentered`
- `testReloadFeedbackAlwaysReturnsToItsRestingOrientation`
- `testReloadFeedbackKeepsTheReloadSymbolUntilRotationCompletes`
- `testTabTrailingControlKeepsAFullHitTargetWithoutGrowingItsGlyph`
- `testCommandPaletteShellUsesOnlyNativeLiquidGlassRendering`
- `testMainBrowserWindowUsesSystemManagedResizableSizingHints`
- `testFreestandingPageFrameUsesOneLockedWidthOnEverySide`
- `testQuickWindowKeepsACompactReadableControlLayer`
- `testQuickWindowUsesStaticSpaceAddressAndOpenChrome`
- `testEveryOnboardingStepFollowsTheSystemAppearance`
- `testEveryPageUsesOneRootLevelFloatingSurface`
- `testCommandPaletteOverlayFadesWithoutScalingItsBackdrop`
- `testSettingsControlsUseOneAccessibleInteractionVocabulary`
- `testTransientEntranceGrowsOnlyTheLayerItsArrangementNames`

Same BrowserNativeWindowControlsHostView adapter is exercised more deeply by testNativeWindowButtonsKeepIdentityAndRestorePlacementAfterRightDocking; remove the duplicate titlebar-style case.

- `testQuickWindowCanAdoptTheMainWindowUnifiedTitlebarMetrics`

## CrestMobileTests/MobileBrowserNavigationTests.swift

Retire settled mobile copy/appearance/spacing/animation snapshots. Native host safe-area geometry, minimum touch targets, actual Reader and content-mode actions, sidebar identity/state and transient safe-area containment remain.

- `testMobileStartPageUsesOnBrandTextAcrossLayouts`
- `testMobileSidebarUsesSpaceForegroundAcrossLayouts`
- `testMobileTabsUseSharedResidencyAppearance`
- `testMobilePageMenuPromotesSafariStyleCommonActions`
- `testCompactPageChromeFloatsOverThePagesThemeBackdrop`
- `testCompactAddressBarUsesSymmetricEdgeControls`
- `testDynamicMobilePageActionsRemainDeferredLocalizedResources`
- `testRootFoldersAlignWithRootSavedTabs`
- `testFolderRowsStepInOneIndentPastTheirFolder`
- `testSplitGroupRowsKeepAStandardSmallGutterBetweenSurfaces`
- `testMobileVariantPickerUsesCompactEmojiGridMetrics`
- `testPeekCardStartsAsOneWebsiteSurfaceAtTheTouchPoint`
- `testPeekUsesTheSharedThemedSplitDestinationAction`
- `testPeekUsesTheSharedFastSpringEntrance`

These call the same platform-independent BrowserVisualAccessibilityPolicy functions already covered by the three corresponding BrowserChromeLayoutTests reduced-transparency/motion tests. No UIKit adapter is exercised.

- `testReducedTransparencyUsesOpaqueAtmosphereAndStrongerScrims`
- `testReducedMotionRemovesCompactSpatialEffects`
- `testReducedMotionDisablesMobileChromeAnimations`

## CrestTests/BrowserSpaceBrandingTests.swift

Retire gallery order/copy/palette and non-nil component render snapshots. Complete platform-image rendering, palette mutation, normalization, versioned persistence, retired vocabulary decoding and bounded render cache tests remain. Gallery composition is a visual review concern.

- `testCuratedPalettesOfferTheNineHouseStartingPoints`
- `testEveryCrestOrdinaryStillRendersThroughItsDedicatedComponent`
- `testEveryChargeIsNamedForTheGalleryCardThatShowsIt`
- `testTheForgeOrdersItsStepsTheWayArmsAreComposed`
- `testTheChargeGalleryNeverShowsTwoCardsThatDrawTheSameFigure`
- `testCuratedPaletteSwatchesNameEveryTinctureTheyShow`
- `testSpaceIdentityArtworkUsesTheLayeredCrestWhenSelected`

## CrestTests/BrowserSidebarInteractionPolicyTests.swift

Retire settled geometry/feature-presence snapshots or duplicate row-height cases. Capability matrix, minimum touch targets, reveal policy and accessibility Dynamic Type cases remain in this suite.

- `testThePointerLeadingGlyphReservesTheSiteControlSquare`
- `testOnlyAFixedBandHeaderStretchesItsTitleToTheRowHeight`
- `testRowsRestAtTheSidebarRowHeightOnEveryShell`
- `testTheNewTabRowSharesTheRowHeightFloor`
- `testATouchShellGivesUpTheClearAction`

## CrestTests/BrowserNavigationFailureTests.swift

Retire error-page paint/style assertions. Native failure publication/retry, cancellation, stale navigation, redirect and external-scheme handling remain in this suite and the mobile adapter suite.

- `testFailureAccentUsesTheSpacePrimaryOrItsOnlyBackgroundColor`
- `testFailureBackgroundUsesOneUniformFillAtEveryCorner`

## CrestTests/BrowserSettingsPaneTests.swift

Retire settled pane-layout/route flags and initializer seams that do not mount or interact with a pane. Shared settings mutation, scoped credential search/deletion, default-browser service behavior and broader touch/Dynamic Type contracts remain.

- `testMacSearchEnginePresentationAndProviderLabelsStayCompact`
- `testOnlyTheMobileHeaderFollowsDynamicTypeForItsTile`
- `testPasswordPaneLayoutsKeepEachShellsShippedShape`
- `testGeneralPaneReadsItsDefaultBrowserSeamFromTheRequestStyle`

## CrestMobileTests/MobileBrowserSettingsPaneTests.swift

Retire fixed presentation/default flags and forwarding to a test-supplied closure. Native Default Apps request tests, supported settings catalog, real shared settings bindings and permission-record distinctions remain. These flags did not prove mounted rename/editor behavior.

- `testSpaceCustomizationKeepsCompactWidthsOnTheStableVerticalLayout`
- `testMobileDefaultBrowserIsChangedThroughSystemSettings`
- `testDefaultSpaceSettingsCapabilitiesAreTheTouchSubset`
- `testMobileSearchEngineManagementDelegatesToTheSpacePage`
- `testMobileSearchEngineEditorUsesManagerNavigation`
- `testMobileBrowsingDropdownsUsePaddedMenuValueLabels`

## CrestTests/BrowserAboutSettingsTests.swift

Retire settled dictionary-forwarding/fallback-copy/URL-literal cases. Archive version checks, release publication and published support-route integrity remain; About highlight filtering/limits remain.

- `testBuildInformationReadsTheShippedBundleKeys`
- `testBuildInformationKeepsUsefulFallbacksForIncompleteBundles`
- `testAboutLinksUseThePublicSupportRoutes`

## CrestTests/BrowserReaderModeTests.swift

Retire static state/action-table snapshots. BrowserPageActionsTests and MobileBrowserNavigationTests invoke the actual Reader bridge and validate activation/restoration; snapshot payload decoding/rejection remains in this suite.

- `testStatesKeepTheirExactToggleAndActivationPolicy`
- `testActionsKeepTheirExactJavaScriptValues`

## CrestTests/BrowserExtensionAPICompatibilityMatrixDocumentationTests.swift

Retire the blanket prose SHA whitelist: legitimate historical citations should not require a runtime matrix change. The retained generator comparison keeps published capability tables aligned with executable routing; verified package/API behavior remains independently tested.

- `testDocumentationRepeatsOnlyPinnedRevisions`

## Scripts/Tests/test_vertical_feature_contract.py

Remove the unit-suite wrapper around the live repository audit under the user-approved narrower scope. Scripts/check-vertical-structure.py remains the direct audit entry point, with seven synthetic positive/negative/debt fixtures retained. Existing source violations are accepted outside the permanent app suite; they are not declared fixed.

- `test_current_repository_matches_the_explicit_debt_ledger`

## Scripts/Tests/test_repository_guardrails.py

Remove the duplicate live-repository scan wrapper consistently with the vertical audit. Scripts/check-architecture.py remains authoritative and its synthetic rejection/exemption fixtures remain. This avoids repeating whole-repository audit state inside unit tests.

- `test_current_repository_satisfies_the_locked_contracts`

## CrestTests/BrowserWebCompatibilityTests.swift

Remove the intermittent combined desktop fixture at the user request. Retained BrowserNavigationPolicyTests cover explicit popup consent/coalescing/reset, BrowserSitePermissionCenterTests cover persistence/Space scope, MobileBrowserInteropTests exercises the shared blocked-message/allow/new-attempt flow, and desktop real-WebKit cases retain block/default/denied behavior and adopted opener/window-close lifecycle. No claim that the missing-notice intermittency was fixed; this exact desktop combined scenario is no longer an automated gate.

- `testAllowingAfterABlockedPopupPersistsAndOnlyNewAttemptOpens`

## CrestTests/BrowserExtensionControllerPoolTests.swift

Retire the intermittent 350-line combined conversion demonstration. Retained verified download/offscreen broker tests protect owning extension/tab/Space and permission dispatch; webpage menu and callback tests protect activation; download transfer tests protect bytes. The exact menu-to-WebP-to-JPEG chain is no longer a permanent gate, an explicit user-accepted reduction in end-to-end coverage.

- `testSyntheticWebPFixtureDispatchesOneClickThroughOffscreenConversionAndCompletesJPEGDownload`

Retire opt-in instrumentation documented as unable to return in XCTest. Keep independent extension storage/Space isolation, native messaging authorization and rehydration, popup port/reload/listener-dispatch tests and opt-in signed-package behavior. No reliable worker-storage/broadcast end-to-end assertion is claimed as a replacement; retire the nonfunctional diagnostic harness under the user-approved maintenance tradeoff.

- `testWorkerStorageWritesAreVisibleToThePopup`
- `testWorkerStorageWritesAreVisibleToThePopupWithoutTheCompatibilityRuntime`
- `testWorkerBroadcastReachesThePopupsOnMessageListener`

## CrestTests/BrowserAddressPresentationTests.swift

Retire the three settled address-display formatting examples. AddressResolverTests still protect navigation parsing; native editing and WindowTitle tests protect current document identity and secret-free fallback titles. Collapsed address display formatting becomes a visual/manual review concern.

- `testAddressPresentationPromotesDomainAndSeparatesTheRoute`
- `testAddressPresentationOmitsARootRoute`
- `testAddressPresentationKeepsNonURLInputReadable`

## CrestTests/BrowserSceneIDTests.swift

Retire the literal scene-ID table and enum-uniqueness tautology. Window/scene ownership, restoration and exact scene dismissal remain covered through their consuming models and native adapters.

- `testSceneIdentifiersAreStableAndUnique`

## CrestTests/BrowserShowcaseSessionTests.swift

Retire assertions about screenshot/demo fixture content and launch aliases. LaunchEnvironmentTests retain isolation from real preferences/data; GettingStarted tests retain real first-run and practice behavior. Demo names, artwork, sample progress and fixture ordering are no longer permanent contracts.

- `testShowcaseSessionIsSafeRichTwoSpaceShowcase`
- `testShowcaseDownloadLedgerIncludesFinishedAndActiveNotifications`
- `testShowcaseLaunchUsesTheShowcaseWithoutChangingPreviewFixtures`
- `testResetLaunchKeepsTheStablePreviewSession`

## Fixture cleanup

Removed the worker diagnostic-only storage/broadcast entry points, timer races, startup control writes, and the unused path that bypassed the compatibility runtime. Kept the common popup fixture and its offscreen creation, sender identity, view enumeration, reload and multi-listener dispatch paths. No new test framework or production abstraction was introduced.
