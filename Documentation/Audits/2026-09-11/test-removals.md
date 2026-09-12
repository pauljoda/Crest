# Method removal and replacement ledger

Names identify baseline methods. Renames and consolidations appear here as replacements, not lost contracts. The suite inventory counts net changes. Retained suites are in `CrestTests/`, `CrestMobileTests/`, and `Scripts/Tests/` at the repository root.

## CrestTests/BrowserAboutSettingsTests.swift

Pins an initial disclosure choice; build metadata, public highlights and display limits remain covered in this suite.

- `testWhatsNewStartsCollapsed`

## CrestTests/BrowserChromeLayoutTests.swift

Pins declared chrome layout flags and decorative metrics; retained native window-button identity/restoration, live page-host preservation, sidebar transitions and accessibility tests exercise the relevant behavior.

- `testAddressControlBelongsToTheSpaceSidebar`
- `testNavigationControlsBelongToTheSpaceSidebar`
- `testArcStyleChromeMovesWithTheSidebar`
- `testWindowToolbarDoesNotReserveASeparateContentStrip`
- `testWindowControlsKeepNativeAppearanceAndBehavior`

Pins decorative dimensions, default disclosure or palette choices. Retained permission access/expansion, foreground readability and native geometry tests cover functional behavior; visual appearance needs rendered review.

- `testSiteControlPopoverUsesCompactURLBarScale`
- `testSitePermissionsStartCollapsedInTheCompactFlyout`
- `testPageSeamRevealsTheContinuousSpaceCanvas`
- `testSettingsVisualPolicyUsesCalmNativeHierarchy`
- `testTabCloseControlUsesPrimaryTextInsteadOfTheSpaceTint`

## CrestTests/BrowserExtensionBackgroundRestartMeasurementTests.swift

Retired historical unload/load measurement. Shipping timeout/error/once behavior remains in BrowserExtensionPopupBackgroundWarmUpTests; context restoration and permission restart remain in BrowserExtensionControllerPoolTests; rehydration remains in BrowserNativeMessagingTests.

- `testRestartingAnExtensionInPlaceIsMeasured`

## CrestTests/BrowserExtensionBackgroundWakeExperimentTests.swift

Retired historical engine-idle experiment. Synthetic tab events are not a shipping recovery strategy; the worker report preserves observations and a historical checkout for reproduction. Shipping recovery owners remain tested.

- `testTabPropertyEventRestartsAnUnloadedBackground`
- `testOpenedTabEventRestartsAnUnloadedBackground`
- `testAnUnloadedBackgroundStaysStoppedWithoutAnEvent`

## CrestTests/BrowserFindBarMetricsTests.swift

Pins decorative pre-merge metrics; capability selection and touch sizing remain covered.

- `testPointerProfileMatchesTheWindowedFindPanel`

Rewritten as testTouchProfileKeepsControlsUsableAndAllowsContentToGrow: retain minimum touch target/content growth, allow decorative metrics to change.

- `testTouchProfileMatchesTheCompactFindBar`

Pins shadow constants; shadows are a visual review concern.

- `testBothShellsLiftTheBarIdentically`

Pins English copy; BrowserFindSessionTests retains search lifecycle and outcomes.

- `testEveryReportedStateCarriesTheWordsBothSpellingsUse`

## CrestTests/BrowserFreshInstallSeedTests.swift

Pins default decorative palette and English preset title. Retained fresh-install seed contract protects one disposable Space; BrowserSpaceBrandingTests protects serialization/versioning and foreground policies protect readability.

- `testFreshInstallSeedWearsTheWinterHousePalette`

## CrestTests/BrowserImportQueueTests.swift

Pins presentation flags rather than import behavior; retained queue order, review navigation and BrowserImportReviewPlanTests protect inclusion, destinations and commit semantics.

- `testArcUsesItsNativeSectionLabelInsteadOfACrestIdentityRow`
- `testImportPreviewKeepsOnlyTheTopSidebarControl`
- `testImportPreviewUsesCalibratedBrandingLanguage`
- `testBrowserChooserUsesTheAnchoredWizardFooter`

## CrestTests/BrowserOnboardingProgressTests.swift

Exact duplicate of testWelcomeStillOffersSetupWhenThisInstallIsIncomplete; never supplies any seed data.

- `testWelcomeOffersSetupForTheDisposableSeedSession`

## CrestTests/BrowserReaderModeTests.swift

Pins localized copy or an internal content-world name; retained reader state/decoding plus BrowserPageActionsTests and MobileBrowserNavigationTests exercise actual reader activation and retained page behavior.

- `testErrorsKeepTheirLocalizedDescriptions`
- `testPresentationCopyResolvesInEnglishAndArabic`
- `testContentWorldNameRemainsStable`

## CrestTests/BrowserSettingsDestinationTests.swift

Consolidated desktop availability/order against the live catalog in testDesktopCanNavigateToEverySettingsDestination. Removed duplicate order/count and trivial id forwarding. Stable existing accessibility raw values remain independently protected without freezing order. Mobile capability exclusions are checked in the mobile target.

- `testIdentityMatchesRawValue`
- `testCatalogOrderIsStable`
- `testPlatformCasesPreserveCatalogOrder`
- `testShortcutsIsTheOnlyPlatformGatedDestination`
- `testDesktopPresentsKeyboardShortcuts`

## CrestTests/BrowserSettingsPaneTests.swift

Unmounted nonoptional body smoke test; builds compile both targets, shared bindings and privacy behavior remain tested.

- `testEverySharedSettingsPaneComposesAgainstAStore`

Unmounted body and identifier snapshot; BrowserPageActionsTests default-zoom persistence and page-pool integration remain.

- `testLookAndFeelPresentsTheSharedDefaultZoomControl`

Unmounted body and identifier snapshot; same suite retains preference configuration and explicit choices.

- `testGeneralSettingsPresentsTheDesktopSpellCheckingControl`

Unmounted body and identifier snapshot; BrowserLinkSettingsTests and platform navigation cover focus preferences.

- `testGeneralSettingsPresentsTheNewTabFocusControlDefaultingOff`

Calls the closure supplied by the test itself; onboarding flow/request/coordinator tests exercise real routing.

- `testAdvancedSetupActionCarriesItsIdentityAndFires`

Pins localized destination copy; platform export and authentication coverage remain.

- `testPlaintextExportNamesEachShellsDestination`

Pins empty-state copy; credential search and privacy tests retain actual filtering/isolation.

- `testEmptyPasswordDescriptionDependsOnWhetherAQueryIsRunning`

## CrestTests/BrowserSidebarInteractionPolicyTests.swift

Consolidated into the four-combination capability matrix and touch-target/content-growth invariants. Decorative glyphs, spacing, opacity and old refactor geometry are no longer frozen; reveal, Dynamic Type, anchors and drag integration remain.

- `testPointerMetricsMatchTheWindowedSidebarRow`
- `testTouchMetricsMatchTheCompactSidebarRow`
- `testRowLayoutFollowsTheLeastPreciseInputTheShellAccepts`
- `testAddingHoverToATouchShellKeepsTheTouchRowLayout`
- `testAddressFieldGeometryFollowsTheShell`
- `testOnlyATouchShellSizesTheClearControlForAFinger`
- `testAddingHoverToATouchShellKeepsTheTouchAddressField`
- `testNavigationStripGeometryFollowsTheShell`
- `testAddingHoverToATouchShellKeepsTheTouchNavigationStrip`
- `testSpaceHeaderGeometryFollowsTheLeastPreciseInputTheShellAccepts`
- `testAddingHoverToATouchShellKeepsTheTouchSpaceHeader`
- `testSpacePickerSegmentsAreSizedForTheAimTheShellAccepts`
- `testAddingHoverToATouchShellKeepsTheTouchSpaceSegment`
- `testAddingHoverToATouchShellKeepsTheTouchControl`
- `testSplitGroupContainerGeometryFollowsTheShell`
- `testSplitGroupBorrowsItsEdgeAndHeaderInsetsFromTheTabRow`
- `testAddingHoverToATouchShellKeepsTheTouchSplitGroupContainer`
- `testTheNewTabRowResolvesEachShellsExactGeometry`
- `testTheTabListResolvesEachShellsSeamAndLandingBand`

## CrestMobileTests/MobileBrowserInteropTests.swift

Renamed/repaired as testPrivateDisguisedExecutableDownloadWaitsForItsSpaceAndCancellationWritesNothing. A user-initiated ordinary executable correctly bypasses the extra prompt; MIME/filename deception must still prompt. Private scope/cancel/no-write assertions remain.

- `testPrivateHostileWebKitDownloadWaitsForItsSpaceAndCancellationWritesNothing`

Shared navigation response policy retained in BrowserNavigationPolicyTests; live mobile download conversion and recovery remain.

- `testUnsupportedResponseTypesBecomeDownloads`

Exact shared ledger case retained in BrowserDownloadLedgerTests.testCompletedRecordCanBeClearedWithoutAffectingAnotherProfile; mobile transfer/isolation adapters retained.

- `testDownloadRecordsRemainProfileScopedAndCanBeClearedIndependently`

## CrestMobileTests/MobileBrowserNavigationTests.swift

Exact shared reload policy retained in BrowserPageActionsTests; mobile zoom/find/reload adapters remain.

- `testMobileReloadPolicyMatchesDesktopAndKeepsHardReloadExplicit`

Exact shared foreground policy retained in BrowserChromeLayoutTests; mobile native chrome and RTL/safe-area coverage remain.

- `testMobileColoredChromeChoosesAReadableForegroundInEveryAppearance`

Stale hard-coded 579pt transition; retained exhaustive width invariant plus boundary transition test protects usable page widths without freezing a former design value.

- `testRegularWindowLayoutProtectsPageWidthAndUsesAnOverlayBelowItsMinimum`

## CrestMobileTests/MobileBrowserPortableArchiveTests.swift

Shared filename constant also checked in BrowserPortableArchiveTests; mobile archive read/write behavior retained.

- `testCanonicalExportFilenameCarriesTheImportableJSONExtension`

## CrestMobileTests/MobileBrowserSettingsPaneTests.swift

Duplicate unmounted nonoptional body smoke checks; both targets compile and owning state/privacy tests remain.

- `testEverySharedSettingsPaneComposesAgainstAStore`

Duplicate default and identifier snapshot; MobileBrowserNavigationTests covers zoom on resident and recreated pages.

- `testMobileLookAndFeelUsesTheSharedDefaultZoomSection`

Shared value policy already exercised for all three layouts in BrowserSettingsPaneTests.

- `testMobilePasswordPaneKeepsTheManagerBehindASheet`

Consolidated capability exclusions and catalog order into testMobileSettingsExposeOnlySupportedDestinationsInCatalogOrder. Removed wrapper identifier echoes; shared stable destination IDs remain covered on macOS. Rendered accessibility remains an integration gap.

- `testMobilePaneWrapperKeepsThePerDestinationIdentifiers`
- `testMobileSettingsNeverOffersTheExtensionsDestination`
- `testMobileSettingsNeverOffersTheWebKitFeatureFlagsDestination`

Shared value policy already covered by testOnlyTheMobileHeaderFollowsDynamicTypeForItsTile; numeric icon dimensions are decorative.

- `testMobileHeaderTileFollowsDynamicType`

Pins equality between two independently configurable decorative palettes; readable foreground policy remains covered.

- `testMobileSelectionWashUsesTheBrandAccent`

Unmounted nonoptional body checks and initializer echoes; default capability test and actual shared binding tests remain.

- `testSharedSpaceSettingsSectionsResolveForBothShellsSubsets`

Unmounted nonoptional body checks; app target builds already type-check these bodies.

- `testEverySharedSpaceSettingsSectionComposesAgainstAStore`

Pins decorative icon spacing; native editor route/keyboard policies remain.

- `testMobileSearchProviderLabelsUseRoomyTouchMetrics`

## CrestMobileTests/MobileToolbarSwipePolicyTests.swift

Explicitly tests an unshipped future mode that switches Spaces, contrary to the shipped cards-only goal.

- `testContextualModeRemainsAvailableAsTheDocumentedFutureSlot`

Pins unused enum possibilities; default routing and mobile command integration remain.

- `testEveryModeAndDestinationStaysAccountedFor`

Repeats shared gesture threshold checks in MobileBrowserNavigationTests and BrowserChromeLayoutTests.

- `testRecognizerThresholdsAreUnchangedByTheNewRouting`

## Scripts/Tests/test_direct_distribution_contract.py

Preflight source sentinel duplicated by executed ReleasePreflightTests.test_unchanged_nightly_skips_scheduled_and_manual_builds.

- `test_unchanged_nightly_stops_before_the_release_job`

## Scripts/Tests/test_product_site.py

Replaced historical editorial/CSS/source-layout snapshots with seven published-site contracts: local destinations/assets, current canonical domain, download/help/privacy/support, manifest icon dimensions/start route, sitemap targets, published guides/legacy redirect and no build-machine paths. Exact visual/copy claims move to review; no rendered layout is claimed.

- `test_product_logo_is_the_site_brand_and_favicon`
- `test_search_and_social_discovery_metadata_is_complete`
- `test_privacy_policy_is_plain_language_complete_and_linked`
- `test_support_page_is_actionable_and_linked`
- `test_hero_uses_layered_space_crests_and_arc_continuation_copy`
- `test_homepage_is_a_full_product_story`
- `test_early_access_and_community_links_are_branded_and_safe`
- `test_arc_parity_matrix_and_carried_forward_story_are_explicit`
- `test_split_view_has_a_real_feature_story_and_help_path`
- `test_spaces_use_an_interactive_cross_platform_showcase`
- `test_published_screenshots_are_current_clean_captures`
- `test_platform_story_portrays_each_device_directly`
- `test_feature_callouts_focus_on_visible_product_behavior`
- `test_extensions_story_is_product_facing_with_details_in_guides`
- `test_help_center_is_reusable_searchable_and_published`
- `test_help_center_covers_the_complete_browser_and_hidden_interactions`
- `test_help_center_navbar_blur_does_not_clip_the_mobile_flyout`
- `test_help_center_preserves_verified_extension_boundaries`
- `test_migration_story_shows_the_real_mac_review_flow`
- `test_homepage_calls_out_arc_inspiration_and_independence`
- `test_public_site_stays_product_facing`
- `test_customization_uses_current_cross_platform_controls`
- `test_customization_media_stays_inside_the_mobile_viewport`

## Scripts/Tests/test_swift_force_unwrap_policy.py

Retired conflicting source heuristic: .swift-format explicitly disables blanket no-force rules. Probe demonstrated false-positive WebKit IUO parameters and a missed forced cast. Runtime crash/safety boundaries remain important; removing the regex does not establish crash freedom.

- `test_app_sources_do_not_force_unwrap_cast_or_try`

## Scripts/Tests/test_xcode_cloud_configuration.py

Pins an Xcode 26 workaround closure spelling and source path. Xcode 27 compiles supported platforms; extension enable/disable/restoration contracts remain in BrowserExtensionControllerPoolTests. No compiler workaround is removed.

- `test_extension_toggle_avoids_xcode_26_setter_thunk_crash`

Pins Xcode 26 closure spelling/file topology, never runs a binding. Onboarding flow and shared binding tests remain; direct UI runtime validation is a separate gap.

- `test_onboarding_bindings_avoid_xcode_26_setter_thunk_crash`
