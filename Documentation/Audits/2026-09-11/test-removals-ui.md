# UI test removal ledger

The user assigns visual appearance, layout, animation, styling and static UI copy to manual review. These 256 methods no longer serve as permanent automated contracts. UI-driven behavior tests remain for ownership, privacy, native input, accessibility semantics, persistence and browsing-state continuity.

## CrestTests/BrowserChromeLayoutTests.swift

Retire visual presentation, geometry, transition and visibility assertions in favor of the user's manual UI review. Functional ownership, navigation/input and persistence contracts remain in this suite and their owning model/native adapter suites.

- `testCompactSpacePickerKeepsItsFullHeightWithLegacyScrollbars`
- `testSpacePickerOverflowTargetsHiddenSegmentsAndStopsAtBothEnds`
- `testOverflowControlsStayInsideTheBalancedPickerBudget`
- `testPinnedExtensionButtonsStayCenteredDuringLayoutChanges`
- `testPinnedExtensionOverflowCanScrollToTheLastButton`
- `testWindowHostedSidebarLiftKeepsLongListsClippedToTheirScrollRegion`
- `testAFolderHeaderPreviewsTheLiftItWouldTake`
- `testCollapsedFolderKeepsTheTabThatWasVisibleWhenItCollapsed`
- `testCollapsingFolderFromAnotherTabHidesEveryFolderTab`
- `testSelectingTabInsideAlreadyCollapsedFolderKeepsItVisible`
- `testSelectingOutsideCollapsedFolderDoesNotHideItsLoadedTab`
- `testReloadingSelectedTabInsideCollapsedFolderKeepsItVisible`
- `testResidencyChangeClearsKeptCollapsedTabAfterExternalUnload`
- `testUnloadingKeptCollapsedFolderTabHidesIt`
- `testSiteControlStaysMountedForAnActiveSiteUntilAddressEditingBegins`
- `testExtensionPopupAnchorsAtTheInvokingControlWithTopLeadingFallback`
- `testExpandedSitePermissionsExposeEveryPermissionControl`
- `testExpandedSitePermissionsGrowTheFlyoutViewport`
- `testCollapsedSidebarLeavesOnlyTheWindowBorderVisible`
- `testEdgeHoverPresentsSidebarWithoutMovingPageContent`
- `testFloatingSidebarWaitsForEverySiteControlSurfaceBeforeDismissing`
- `testFloatingSidebarUsesTheFullSpaceThemeAndItsSidebarButtonDocks`
- `testHidingSidebarKeepsItsUndockedSurfaceWhileHovered`
- `testHidingSidebarDismissesAfterMorphWhenPointerIsAway`
- `testDockingSidebarMakesRoomBeforeAttachingItsCard`
- `testReducedMotionDocksSidebarWithoutAnApproachPhase`
- `testFloatingSidebarWaitsForCommonListsBeforeDismissing`
- `testClosingCommonListsKeepsHoveredFloatingSidebarPresented`
- `testReducedMotionCollapsesSidebarWithoutAnIntermediateSurface`
- `testReducedMotionRetainsHoveredSidebarWithoutAnimating`
- `testDockedSidebarKeepsNativeWindowControlsAndLayoutWidth`
- `testDockedSidebarReplacesOnlyTheLeadingPageFrameEdge`
- `testEmbeddedPrivateLockKeepsTheOwningSpaceSwitcherAsTheOnlySelector`
- `testCompactSpaceStripAccessibilityOrderMatchesVisualOrder`
- `testCompactSpaceStripUsesOverflowAtBoundaryCountsAndWidths`
- `testCompactSpaceStripAlwaysTargetsTheActiveSurvivingSpace`
- `testFreshLoadingPageShowsOpeningStatusUntilItsFirstCommit`
- `testPendingNavigationShowsProgressBeforeTheFirstCommit`
- `testCompletedPageHidesProgressDespiteAPendingDestination`
- `testRealLoadsKeepProgressVisibleAfterTheFirstCommit`
- `testIdlePagesWithoutPendingNavigationHideProgress`
- `testPageLoadingProgressStartsVisibleAndStaysWithinItsTrack`
- `testPeekUsesAnUncappedEightyPercentDesktopCardAndSharedSpringEntrance`
- `testQuickWindowCentersWithinSourceWebContentInsteadOfDisplay`
- `testQuickWindowKeepsTheFrameChosenByTheUserAfterInitialPlacement`
- `testBrowserChromeClipsItsThemeFrameToFullscreenWindowBounds`
- `testBrowserChromeHidesItsOwnedToolbarInFullscreen`
- `testPeekNormalizesItsSourceToTheWebViewClickPoint`
- `testCommandPaletteResultAreaSizesToItsContentBeforeScrolling`
- `testReducedTransparencyRemovesAtmosphereAndStrengthensCustomScrims`
- `testReducedMotionRemovesCustomSpatialChromeEffects`
- `testReducedMotionDisablesAppAuthoredChromeAnimations`
- `testColoredChromeChoosesAReadableForegroundInEveryAppearance`
- `testSemanticLeadingGeometryMirrorsInRightToLeftLayouts`
- `testTransientCardArrangementsKeepEachShellsOwnReach`
- `testTransientCardSizesFollowTheRoomEachArrangementIsGiven`
- `testMeasuredContentBoundsCenterPaletteOnEitherSidebarSideAndReadingDirection`
- `testNativeWindowButtonsKeepIdentityAndRestorePlacementAfterRightDocking`

## CrestMobileTests/MobileBrowserNavigationTests.swift

Retire visual presentation, geometry, transition and visibility assertions in favor of the user's manual UI review. Functional ownership, navigation/input and persistence contracts remain in this suite and their owning model/native adapter suites.

- `testEmptyMobilePageBackgroundIsClearUntilWebKitFinishesContent`
- `testCompactToolbarCanCollapseToADomainChipAndReexpand`
- `testOpeningAnotherCompactTabRestoresTheFullToolbar`
- `testLockKeepsTheFloatingPhoneSidebarOverThePage`
- `testLockRevealsACollapsedFloatingPhoneSidebar`
- `testLockKeepsTheDockedPhoneInItsFullscreenTabViewer`
- `testLockedFloatingSidebarDoesNotAutoDismiss`
- `testPrivateSpaceLockCentersAnUngroupedDetailSurface`
- `testLockedSpaceExitPreservesDockedAndFloatingSidebarModes`
- `testCompactPresentationStartsWithTheFullScreenSidebar`
- `testCompactTabViewerKeepsItsChromeOutOfThePresentedPage`
- `testCompactTabViewerDismissesDirectlyToItsStableMatchedSource`
- `testCompactPagePrepositionsOnlySourcesThatChangeBehindThePresentedPage`
- `testCompactPageMorphTargetsPinnedSavedAndCurrentTabs`
- `testOnlyExpandedContainersUseTheRegularBrowserPresentation`
- `testCompactSidebarUsesItsFullScreenViewerAsTheDockedState`
- `testBorderlessAppearanceAppliesToDockedAndSplitPages`
- `testOnlyDockedPhoneDetailsAndSplitViewKeepTheCompactToolbar`
- `testOnlyFloatingKeyboardsIgnoreTheKeyboardSafeArea`
- `testRegularPageFrameOnlyAdjoinsASideBySideSidebar`
- `testEverySupportedStageManagerWidthPreservesEitherAUsablePageOrAnExposedPageEdge`
- `testRegularSidebarVisibilitySurvivesStageManagerLayoutTransitions`
- `testTransientRegularSidebarDismissesAfterItsIdleDelay`
- `testTransientRegularSidebarPausesWhileATabIsBeingDragged`
- `testPinnedGridRetainsTheMeasuredArcColumnCounts`
- `testMobileLeadingChromeMirrorsForRightToLeftLayout`
- `testCompactWebFrameExtendsBehindTheToolbarWhileReportingItsObscuredArea`
- `testResolvedSafeAreaFollowsTheReadingDirectionIntoWebKitsGeometry`
- `testTheInlineViewportLeavesEveryInsetToTheContainer`
- `testCompactWebHostKeepsScrollingContentFullHeightForExpandedAndCollapsedToolbars`
- `testSplitCardCellsAbsorbTheSameTopSafeAreaAsTheSinglePage`
- `testHiddenToolbarUsesASmallerVisualChipWithoutShrinkingItsTapTarget`
- `testTransientCardsStayInsideTheSafeAreaInEveryDirection`
- `testPeekCloseAndSpaceControlsShareOneMinimumHitHeight`
- `testMobileLinkPeekSuppressesWebKitsTransientLinkHighlight`
- `testMobilePageUsesStandardsThemeColorForItsSurroundingWebView`

## CrestTests/BrowserFindBarMetricsTests.swift

Retire the complete visual metrics/color/catalog/menu presentation suite under the user's manual UI review policy. Find/search behavior, settings writes, extension panel routing/ownership, and drag/drop mutations remain tested at their owning layers. Literal automation identifiers are not a product compatibility gate.

- `testTouchAloneDecidesWhichProfileTheBarDrawsWith`
- `testTouchProfileKeepsControlsUsableAndAllowsContentToGrow`

## CrestTests/PinnedTabGridLayoutTests.swift

Retire the complete visual metrics/color/catalog/menu presentation suite under the user's manual UI review policy. Find/search behavior, settings writes, extension panel routing/ownership, and drag/drop mutations remain tested at their owning layers. Literal automation identifiers are not a product compatibility gate.

- `testCustomizedPinsKeepTargetsAndDragGapInsideNarrowGrid`
- `testPinnedTabsUseTheSameResidencyAppearanceAsOtherTabs`
- `testScaledPinsBalanceRowsAndPreserveProportions`
- `testGridUsesEveryAvailableColumnForOneThroughFourPins`
- `testGridBalancesArcStyleRowsForFiveThroughTwelvePins`

## CrestTests/BrowserSpaceForegroundPolicyTests.swift

Retire the complete visual metrics/color/catalog/menu presentation suite under the user's manual UI review policy. Find/search behavior, settings writes, extension panel routing/ownership, and drag/drop mutations remain tested at their owning layers. Literal automation identifiers are not a product compatibility gate.

- `testDarkBrandingUsesLightForegroundContent`
- `testBrightBrandingUsesDarkForegroundWhenItHasBetterContrast`
- `testMixedBrandingProtectsTheDarkestRegion`
- `testDesignSystemMapsForegroundToneToTheMatchingSystemScheme`

## CrestTests/BrowserSettingsDestinationTests.swift

Retire the complete visual metrics/color/catalog/menu presentation suite under the user's manual UI review policy. Find/search behavior, settings writes, extension panel routing/ownership, and drag/drop mutations remain tested at their owning layers. Literal automation identifiers are not a product compatibility gate.

- `testRawValuesPinTheAccessibilityIdentifierContract`
- `testDesktopCanNavigateToEverySettingsDestination`

## CrestTests/BrowserExtensionSidebarSwitcherMenuModelTests.swift

Retire the complete visual metrics/color/catalog/menu presentation suite under the user's manual UI review policy. Find/search behavior, settings writes, extension panel routing/ownership, and drag/drop mutations remain tested at their owning layers. Literal automation identifiers are not a product compatibility gate.

- `testRowsCarryTheTitleTheCheckedPanelAndTheExtensionsOwnArtwork`
- `testAPanelWithoutArtworkFallsBackToTheTemplatedPuzzlePiece`
- `testASoleAvailablePanelDoesNotEarnASwitcher`
- `testAPanelThatIsNoLongerPresentedLeavesEveryRowUnchecked`

## CrestTests/BrowserSidebarInteractionPolicyTests.swift

Retire visual presentation, geometry, transition and visibility assertions in favor of the user's manual UI review. Functional ownership, navigation/input and persistence contracts remain in this suite and their owning model/native adapter suites.

- `testTouchTargetsRemainUsableAndTextContainersCanGrow`
- `testCompactIconPickerLetsTheSystemChooseAVerticalEdge`
- `testOnlyATouchAddressFieldGrowsPastItsRestingBand`
- `testTheSpaceSwitcherScrollsExactlyWhereTheShellAcceptsTouch`
- `testEachSegmentFitsTheTrackItsArrangementDrawsItIn`
- `testOnlyAShellWithoutTheNativeZoomAnchorsWithMatchedGeometry`
- `testARowAnchorsNothingWhereNoSurfaceGrowsOutOfIt`
- `testTheWindowedShellStillPairsItsRowsWithTheSurfaceTheyGrow`
- `testAPinnedTileClaimsAnAnchorOnlyWhereThereIsOneToPairWith`
- `testDefeatingThePairingRequirementRestoresThePartnerlessTileAnchor`
- `testAPinnedTileWithNoNamespaceClaimsNothing`
- `testOnlyATouchShellGrowsItsRowsAtAnAccessibilityTextSize`
- `testOnlyATouchShellKeepsSplitMembersAtFullRowHeight`
- `testAGroupedMemberLeavesTheInsertionLinesToItsContainer`
- `testSplitGroupIconDeckRaisesTheFocusedMemberAboveItsPeers`
- `testSplitGroupIconDeckAdmitsAFocusedMemberBeyondItsVisibleLimit`
- `testSplitGroupIconDeckKeepsOrdinaryOrderWithoutAFocusedMember`

Retire control/reveal visibility and reset-menu availability rules under manual UI review. Input capability resolution remains; actual scoped icon mutations and native input routing remain in owning suites.

- `testAutomaticWebsiteFaviconDoesNotOfferAResetAction`
- `testOnlyDeliberateTabIconOverridesOfferAResetAction`
- `testControlsHideUntilHoverOnlyWhereHoverExistsAndTouchDoesNot`
- `testRevealMatrixFollowsTheShellRatherThanTheRow`

## CrestTests/BrowserSpaceBrandingTests.swift

Retire artwork existence/rendering, contrast, editor labels and color-role presentation checks. Branding persistence/migration, scoped mutations, normalization and bounded rendering-cache behavior remain. Visual quality is manually reviewed.

- `testGradientControlsSupportKeyboardAndSemanticFineTuningLabels`
- `testEveryCrestChargeResolvesBundledArtworkOrASystemSymbol`
- `testEveryPlateDivisionAndBandDrawsAPath`
- `testDefaultCrestFieldContrastsWithTheBannerBackground`
- `testAutomaticallyCreatedSpacesStartWithAHigherReadabilityFade`
- `testSpaceSymbolArtworkRendersLayeredCrestAsOnePlatformImage`
- `testRoleColorsUseTheNearestConfiguredSlotAsFallback`
- `testGradientThemeRendersAsAPlatformImage`
- `testGradientTextureProducesAPerceptibleRenderedDifference`

## CrestTests/BrowserFolderAppearanceTests.swift

Retire color, highlight and compositing presentation expectations. The retained binding/sync round trip covers textColorMode and folderColorIntensity, plus missing/future values and Space isolation.

- `testTextColorOverridesBothContrastingPalettesAndReturnsToAutomatic`
- `testColorStrengthKeepsExistingEndpointsAndClampsInvalidValues`
- `testPersistentHighlightsDoNotReplaceInteractionFeedback`
- `testTextToneUsesTheCompositedColorAtIntermediateIntensity`

## CrestTests/BrowserFullscreenChromeTests.swift

Retire visual presentation, geometry, transition and visibility assertions in favor of the user's manual UI review. Functional ownership, navigation/input and persistence contracts remain in this suite and their owning model/native adapter suites.

- `testCollapsedSidebarKeepsNativeWindowControlsInFullscreen`

## CrestTests/BrowserCredentialFieldAnchorTests.swift

Retire prompt placement and width expectations. Retain hostile geometry validation, main-frame/form ownership, dismissal and real isolated credential bridge behavior.

- `testAnchoredPromptSitsUnderItsFieldAndFlipsRatherThanLeaveThePage`
- `testAnchoredPromptTakesTheFieldsWidthInsideTheProfilesBounds`

## CrestTests/BrowserWebHostViewTests.swift

Retire native viewport sizing and layout-repair fixtures. Stale-host ownership, reparenting, native key/focus routing and real WebKit input/selection survival remain; appearance-change document continuity remains in ChromeLayoutTests.

- `testAttachUsesFrameLayoutForWebKitsReparentedSurfaces`
- `testAttachingAResidentPageToANewHostPreservesItsViewport`
- `testAnEmptyHostLayoutDoesNotDiscardAResidentViewport`
- `testLayoutRepairsAnAttachedPreloadedWebViewsStaleGeometry`

## CrestTests/BrowserSplitColumnLayoutTests.swift

Retire column, divider, z-order and placeholder visual geometry examples. Retain invalid-data normalization, resize operations/limits, membership proportions and durable commit boundaries; actual scoped drop/reorder mutations remain in owning suites.

- `testFocusedCardDrawsAboveItsRestingSiblings`
- `testEqualFractionsShareTheWidthLeftByTheGaps`
- `testUnnormalizedFractionsLayOutLikeTheirNormalizedForm`
- `testACardTooNarrowForItsShareIsFlooredAtTheMinimum`
- `testFlooringRedistributesToEveryCardStillAboveTheFloor`
- `testAContainerTooNarrowForItsCardsFloorsThemAndClips`
- `testAContainerExactlyAsWideAsTheFloorsStillTotals`
- `testASingleCardTakesTheWholeContainerWithNoGapToPay`
- `testEveryDividerSitsCenteredOnTheGapItMoves`
- `testTheDividerFollowsTheDragThatMovesIt`
- `testThePlaceholderBesideALoneCardIsExactlyHalfTheRow`
- `testThePlaceholderTakesAThirdBesideTwoAndAQuarterBesideThree`
- `testTheDropColumnFloorsAtTheMinimumLikeEveryOtherColumn`
- `testAResizedSplitKeepsItsProportionsAroundTheDropColumn`
- `testAnEmptySplitGivesThePlaceholderTheWholeRow`

## CrestTests/BrowserSplitPanelLayoutTests.swift

Retire exact panel sizing and member-width allocation. Nonfinite/negative geometry safety, one-time resize commits, distinct panel identity and divider input exclusion remain.

- `testPanelReservesItsWidthWithoutJoiningMemberFractions`
- `testPanelYieldsBeforeFourMemberCardsClip`
- `testRequestedPanelWidthIsClampedAndInvalidValuesUseDefault`

## CrestTests/BrowserSplitPanelViewportTests.swift

Retire the visual responsive/fixed-width panel fitting fixture and sizing examples. Requested zoom persistence, active-page command routing and resident/recreated zoom are retained in BrowserPageActionsTests; general live document/host continuity remains in BrowserChromeLayoutTests. Automatic panel-fit appearance and its exact combined sequence move to manual review.

- `testOpeningAndResizingPanelUpdatesTheResidentPageViewport`
- `testFittingOnlyReducesZoomWhenAnAuthoredMinimumExceedsTheCard`

## CrestTests/BrowserSplitCardLiftTests.swift

Retire carried-card positioning and snapshot transition expectations. Native pickup routing, scoped member identity, staged/one-time commits, cancellation and rejection of stale snapshots remain.

- `testTheGrabFractionIsWhereInsideTheCardThePointerLanded`
- `testTheGrabFractionStaysInsideTheCard`
- `testTheGrabbedPointStaysUnderThePointer`
- `testTheSnapshotCrossfadesInWhenWebKitAnswers`
- `testASnapshotArrivingDuringTheSettleIsStillShown`

## CrestTests/BrowserSidebarWidgetRuntimeTests.swift

Retire deck depth, spacing, fade, rubber-banding and height presentation expectations. Worker lifecycle, bounded input accumulation, committed selection, platform filtering and profile/runtime behavior remain.

- `testDeckOrderStartsAtTheSelectedCardAndWrapsToFillVisibleDepth`
- `testDeckDragTracksPartiallyAndRubberBandsBeyondItsLimit`
- `testSideStepperNeverConsumesCardWidth`
- `testSideStepperSelectionDoesNotChangeDotGeometry`
- `testOnlyRecedingCardsFadeTheirContentBehindTheFrontCard`
- `testDeckSlotOffsetKeepsAPredictablePeekUnderTheFrontCard`
- `testCarouselHeightTracksOnlyMeaningfulSelectedCardChanges`

## CrestMobileTests/MobileBrowserSidebarWidgetPolicyTests.swift

Retire sidebar visibility presentation checks. Private browsing suppression, supported mobile capabilities and native drag-axis routing remain.

- `testWidgetHostRendersInDockedAndFloatingSidebars`
- `testWidgetHostIsAbsentWhenTheSidebarIsCollapsed`

## CrestTests/BrowserExtensionsPresentationTests.swift

Retire extension status/detail/issue wording and display-state examples. Runtime failure classification, actual compatibility/broker behavior, exact options ownership and minimum reviewed access grants remain tested. User-facing compatibility explanations are manually reviewed.

- `testRunningExtensionDetailUsesSingularCounts`
- `testDisabledExtensionDetailUsesPluralCounts`
- `testLoadedExtensionWithCompatibilityErrorNeedsAttention`
- `testRuntimeFailureIsExplainedWithoutLeadingWithJavaScript`
- `testRuntimeDiagnosticsKeepAWorkingExtensionRunning`
- `testBlockingCompatibilityFailureExplainsWhyExtensionCannotRun`
- `test1PasswordSafariFailureExplainsTheActualUserImpact`
- `test1PasswordChromeRuntimeFailureDoesNotBlameProductionSigning`
- `testICloudPasswordsLimitationRemainsVisibleAfterInstallation`
- `testCompatibilityErrorUsesPresentationOwnedDescription`

## CrestTests/BrowserPageActionsTests.swift

Retire percentage-label formatting; actual zoom command routing, persistence and bounds remain in the same suite.

- `testZoomPercentageLabelRoundsForDisplay`

## CrestTests/BrowserSettingsPaneTests.swift

Retire confirmation copy assertions. Credential deletion scope and authorization remain tested in credential model/store/action suites; confirmation wording is manually reviewed.

- `testDeletionMessageNamesTheScopeAndTheSynchronizedCopy`

Retire app-icon catalog appearance/dimensions and chooser resource examples under manual UI review. Native Dock plug-in loading and saved settings behavior remain.

- `testEveryOfferedMacAppIconLoadsFromTheBuiltCatalog`

## CrestMobileTests/MobileBrowserSettingsPaneTests.swift

Retire UI destination catalog/order checks; actual settings bindings, permissions and platform action behavior remain.

- `testMobileSettingsExposeOnlySupportedDestinationsInCatalogOrder`

## CrestTests/BrowserWindowTitleTests.swift

Retire title formatting preference examples; secret redaction, Space/window ownership and live metadata updates remain.

- `testCustomTabTitleWinsAndWhitespaceRenameReturnsToPageTitle`

## CrestTests/BrowserMacDownloadFeedbackTests.swift

Retire download animation geometry and reduced-motion presentation cases. Context rejection, consumed-event identity and bounded in-flight feedback remain; transfer lifecycle remains independently tested.

- `testFlightArcsUpwardShrinksAndEndsAtArchive`
- `testReduceMotionAndInvalidGeometryUseStaticFeedbackAndExpirationClearsIt`

## CrestTests/BrowserSoftwareUpdateTests.swift

Retire update UI presence/route and release-note formatting assertions. Signed feed/channel selection, consent/actions, exact-build dismissal, download/install lifecycle and runtime ownership remain.

- `testEveryNonIdleUpdaterStateHasASidebarPresentation`
- `testChangelogUsesAnExplicitDetailsSceneInsteadOfTheOldUpdateWindow`
- `testReleaseNotesPreserveMarkdownBlockHierarchy`
- `testReleaseNotesKeepWrappedParagraphsTogether`

## CrestTests/BrowserUtilityListTests.swift

Retire utility menu order, fan transition and icon catalog assertions. Search/filter data, list preparation, exact Space/profile reconciliation, archive ordering and file actions remain.

- `testCommonListSwitcherKeepsTheThreeRequestedDestinationsInOrder`
- `testUtilityFanStartsRevealingBeforeItsFirstSuspension`
- `testDownloadFileIconsReflectCommonFileKinds`
- `testArchiveFiltersIncludeEveryRemovalCauseWithASymbol`

## CrestTests/BrowserSidebarReorderLayoutTests.swift

Retire projected row/grid frames, placeholder dimensions and landing-animation expectations. Retain native drag session identity, parent/nesting target resolution, hidden descendant drop-zone exclusion, autoscroll target stability and actual folder/tab reorder mutations.

- `testMovingAnExpandedFolderClosesItsWholeSourceAndOpensExactlyOneGap`
- `testMovingUpDisplacesAllFollowingSectionsWithoutDoubleMovingDescendants`
- `testNestingExpandsTheParentBoundaryAroundTheGap`
- `testLeavingTheSidebarClosesTheSourceWithoutCreatingAnotherGap`
- `testPinnedTilesAndOtherColumnsDoNotMoveWithTheScrollingList`
- `testIncomingFifthPinnedTabReflowsIntoTwoRowsWithoutLosingTheGap`
- `testPinnedSourceLeavingClosesItsSlotAndShrinksTheGrid`
- `testReleaseKeepsOnePreviewUntilItsMeasuredLandingCompletes`
- `testPinnedPreviewPreservesGrabFractionAndStaysInsideTheLeftEdge`

## CrestTests/BrowserSplitWidthTransactionTests.swift

Retire pointer/divider geometry examples, including the deliberate wrong-implementation counterexample. Retain accessibility resizing and live-versus-durable commit/adoption behavior; actual pair-resize bounds remain in SplitColumnLayoutTests.

- `testAStationaryPointerLeavesTheLayoutWhereItIs`
- `testTheDividerConvergesOnThePointerItIsMeasuredAgainst`
- `testMeasuringAgainstTheMovingDividerWouldNeverSettle`

## CrestTests/BrowserSidebarHoverTrackingTests.swift

Retire sidebar hover/menu visibility timing and reveal geometry scenarios under manual UI review. Retain actual native click/drag pass-through; exact target ownership and key/mouse routing remain in separate native adapter suites.

- `testMenuDismissedInsideKeepsSidebarOpenWithoutAnotherMouseEvent`
- `testMenuDismissedOutsideHidesWithoutAnotherMouseEvent`
- `testNestedMenusHoldUntilEveryTrackedMenuCloses`
- `testRepeatedMenusResampleBothEdgesOfTheFullHoverRegion`
- `testMenuOutsideSidebarDoesNotHoldItOpen`
- `testDisabledOrDetachedTrackerCannotKeepAStaleMenuHold`
- `testOffscreenGeometryAtRevealIsNotReportedAsAnExit`

## CrestTests/BrowserInteractionModelTests.swift

Retire drag preview/morph, indicator visibility, interpolation, displacement and tint expectations. Retain exact drop target resolution, platform drag completion, cancellation, captured ownership and durable reorder behavior. Visual feedback moves to manual UI review.

- `testMobileInsertionSlotHasOneVisibleIndicatorOwner`
- `testMobileSourceStylingRequiresAReliableTerminalLifecycle`
- `testTransientDropExitDoesNotFlashTheIndicatorDuringTargetHandoff`
- `testDeferredDropExitClearsAnAbandonedIndicator`
- `testHeldTabPreviewInterpolatesFromRowToPinnedTile`
- `testThePlacementPreviewEntryIsTheRowToPinnedTilePair`
- `testHeldTabPreviewInterpolatesFromRowToWebpageCard`
- `testAPointerAnchoredPreviewSitsWhereTheInRowPreviewWouldHave`
- `testALiftFloatsForTheWholeOfItsLiftWhereverThePointerGoes`
- `testFoldersAndSplitGroupsFloatAsRows`
- `testDisplacementOpensAGapAndClosesTheVacatedSlot`
- `testTheEmptyUnfiledSavedRunDrawsItsOwnInsertionLine`
- `testEveryEmptySectionDrawsTheLineItsRowsWouldHave`
- `testAnEmptySectionShowsNothingWithoutAResolvedTarget`
- `testGridDisplacementWrapsAcrossColumns`
- `testALiftedSplitGroupNeverTakesAMorphTargetPlacement`
- `testAPinnedLiftHoldsItsTileShapeUntilAListResolves`
- `testPinnedTabAccentPrefersSiteThemeThenExtractedColorThenWhite`

## CrestTests/BrowserCommandPaletteTests.swift

Retire action-row icon/copy and section height/spacing expectations. Retain search/ranking, result identity, stale-response rejection and actual action routing.

- `testAnActionRowCarriesItsSectionNameAndAGlyph`
- `testASectionedListPaysForEveryHeaderAndEveryGapBetweenSections`
- `testALongSectionedListStopsGrowingAndScrollsInstead`

## CrestTests/BrowserSpaceAccessTests.swift

Retire unlock label layout/Dynamic Type size comparisons. Authentication authorization, late completion after relock, exact Space/profile identity and persisted access policy remain.

- `testUnlockLabelKeepsItsSizeDuringAuthentication`

## CrestTests/BrowserPageNavigationMarkerTests.swift

Retire empty-page backdrop opacity. Navigation marker consumption, stale commit rejection and committed/completed navigation state remain.

- `testEmptyPageBackgroundIsClearUntilWebKitFinishesContent`

## CrestTests/BrowserSystemNowPlayingTests.swift

Retire artwork aspect-ratio appearance examples. Background-thread artwork safety, media ownership and native command dispatch remain.

- `testSystemArtworkPreservesWideAndTallSourceAspectRatios`

## CrestTests/BrowserTabMultiSelectionTests.swift

Retire batch row displacement and placeholder height expectations. Atomic multi-selection moves, Space authorization, pin capacity, cancellation and durable follow/commit behavior remain.

- `testBatchLayoutClosesOnlySelectedIntervalsAndReservesTheirCombinedHeight`

## CrestTests/SpaceScrollGestureTests.swift

Retire compositor decoration synchronization (highlight, toolbar opacity, backdrop and icon-lane animation). Native gesture normalization, terminal/invalidated gestures, bounded burst handling and exact selection commits remain.

- `testSpaceDecorationsKeepPaceWithNativeSettlementWithoutProgressCallbacks`

## Focused retained tests

Four mixed tests were renamed after their visual assertions were removed:

- `testPeekUsesOneThemedSplitActionAcrossPlatformsAndSupportsDirectKeys` → `testPeekKeyboardDismissalLeavesReturnToThePage`
- `testEveryCrossSectionDropShowsTheSectionWhereItWillLand` → `testCrossSectionDropsResolveTheDestinationSectionAndIndex`
- `testALiftCrossingIntoAFolderScopedSectionDisplacesItsRows` → `testALiftCrossingIntoAFolderScopedSectionResolvesItsRows`
- `testAFolderHoldingEverySavedTabOpensAGapForACurrentLift` → `testAFolderHoldingEverySavedTabResolvesACurrentLift`

The Peek case now checks keyboard dismissal and leaves Return to the page. The three drag cases keep all eight retained cross-section scenarios and assert exact destination sections/indices. Their fixtures no longer calculate row displacements or indicator arrays. Other mixed tests retain border migration, startup preference behavior, native page/document continuity and drag-target stability while dropping pixel, spacing and copy expectations.

Unused scroll-view/button search helpers, sidebar morph continuations, render-pixel extraction and divider/preview geometry helpers were removed. Six whole suites were removed with their fixtures. No replacement visual test framework or permanent diagnostic harness was added.
