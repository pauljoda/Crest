# Test retention and cleanup

Reviewed baseline: `457ac1d2c9bc78011e595664053f24df50ae2249`, 2026-09-07. Counts below distinguish the reviewed baseline from the bounded cleanup applied alongside this audit.

The permanent suite should protect behavior whose failure matters: browsing and state transitions, persistence and migration, privacy and authorization, extension compatibility and recovery, and measured performance limits. It should not require updates whenever a decorative constant, helper name, or file location changes. A test's age, size, or origin in a bug report does not determine its value.

**Applied cleanup:** removed 11 test methods and seven redundant extension assertions, totaling 209 lines across six test files. No production code or complete test file was removed. The retained affected suites passed: **221 Swift tests and 11 Python tests, zero failures**. This is a maintenance improvement; no suite-speed improvement was measured.

## Inventory

Counts are declared test methods, not a claim that every method ran during this audit. Three private Mac helpers whose names start with `test` are excluded from method counts. File and line totals include test helpers in the named directories; generated fixtures are excluded from Swift counts.

| Source | Files at baseline | Methods before | Methods after |
| --- | ---: | ---: | ---: |
| `CrestTests/*.swift` | 236 | 2,945 | 2,935 |
| `CrestMobileTests/*.swift` | 36 | 436 | 436 |
| `Scripts/Tests/test_*.py` | 18 | 169 | 168 |
| Total | 290 | 3,550 | 3,539 |

The baseline contains 122,706 raw Swift test lines and 5,123 Python test lines. Method count alone does not measure useful coverage or execution cost. The extension assertion cleanup changes no method count.

| Python responsibility | Files | Baseline methods |
| --- | ---: | ---: |
| Release, version, signing, and publication | 7 | 56 |
| Repository architecture, formatting, and public-source contract | 3 | 23 |
| Xcode Cloud and CloudKit environment | 2 | 12 |
| Reference corpus, emoji generation, and roadmap rendering | 3 | 33 |
| Release soak | 1 | 20 |
| Product website | 1 | 24 |
| Force-unwrap source heuristic | 1 | 1 |

The architectural guardrails use synthetic valid and invalid repositories as well as scans of the current repository. These are materially different from tests that require an individual feature to retain a particular filename. A targeted scan found no clear Swift test that asserts production Swift declaration placement or file topology. Many Swift source reads load fixtures, execute generated JavaScript, check vendor-byte preservation, or verify published extension documentation; those uses are not inherently bloat.

## Applied method removals

Names in this table refer to removed baseline methods. Links point to the surviving owning suites.

| File and removed methods | Reason and retained protection |
| --- | --- |
| [BrowserShortcutTests](../../../CrestTests/BrowserShortcutTests.swift): `testArcAlignedDefaultsCoverEverydayNavigationAndPageCommands`, `testSplitViewDefaultsTakeTheArrowAndUnsplitChordsZenUses` | Both repeat subsets of the retained exhaustive command/raw-value/default-chord catalog. Keep the catalog because stable command IDs and familiar chords are real compatibility contracts. |
| [BrowserChromeLayoutTests](../../../CrestTests/BrowserChromeLayoutTests.swift): `testDownloadsShortcutMatchesInstalledArcAndClick`, `testStopLoadingShortcutMatchesInstalledArc` | These repeat two entries in that same catalog and do not exercise chrome or command dispatch. |
| [BrowserChromeLayoutTests](../../../CrestTests/BrowserChromeLayoutTests.swift): `testAddressControlUsesCompactArcAlignedMetrics` | Pins three decorative constants. Removing it permits deliberate visual changes without updating an implementation snapshot; it does not remove gesture direction, split geometry, window ownership, or presentation-state coverage. |
| [BrowserSidebarInteractionPolicyTests](../../../CrestTests/BrowserSidebarInteractionPolicyTests.swift): `testNavigationChevronsAreSizedForTheShellTheyAreAimedAtWith`, `testOnlyAnAlwaysVisibleCloseControlDimsOnAnUnselectedRow` | Pins font choices and exact opacity values. Retained tests cover touch/hover reveal behavior, touch target sizing, mixed touch-and-hover input, and accessibility text-size behavior. Exact appearance is no longer treated as an immutable unit-test contract. |
| [BrowserSettingsPaneTests](../../../CrestTests/BrowserSettingsPaneTests.swift): `testPaneHeaderKeepsEachShellsIdentifierContract`, `testPaneHeaderLayoutsKeepTheirShippedMetrics`, `testPaneHeaderDrawsTheDestinationsOwnBrandHue` | The first checks that an initializer stores its explicitly supplied identifier; it does not inspect the rendered accessibility tree or actual platform caller. The other two pin decorative values and branding choices. Shared-pane composition and mobile Dynamic Type behavior remain tested. Automation identifiers remain an integration concern; this deletion does not establish rendered identifier coverage. |
| [test_repository_guardrails.py](../../../Scripts/Tests/test_repository_guardrails.py): `test_repository_formatter_uses_four_space_indentation` and its now-empty class | Repeats three values already declared in `.swift-format`. The formatter configuration and formatting tools remain authoritative; the test did not demonstrate formatting behavior. All 11 retained repository guardrail tests pass. |

Specific retained coverage includes:

- [Complete shortcut catalog](../../../CrestTests/BrowserShortcutTests.swift#L153), [duplicate-chord rejection](../../../CrestTests/BrowserShortcutTests.swift#L6), [custom/unassigned persistence](../../../CrestTests/BrowserShortcutTests.swift#L49), and [versioned storage shape](../../../CrestTests/BrowserShortcutTests.swift#L272).
- [Touch/hover reveal policy](../../../CrestTests/BrowserSidebarInteractionPolicyTests.swift#L65), [touch target metrics](../../../CrestTests/BrowserSidebarInteractionPolicyTests.swift#L110), [touch with hover](../../../CrestTests/BrowserSidebarInteractionPolicyTests.swift#L653), and [accessibility text sizing](../../../CrestTests/BrowserSidebarInteractionPolicyTests.swift#L686).
- [Shared settings composition](../../../CrestTests/BrowserSettingsPaneTests.swift#L112) and [mobile Dynamic Type](../../../CrestTests/BrowserSettingsPaneTests.swift#L258).
- [Bidirectional reveal gestures](../../../CrestTests/BrowserChromeLayoutTests.swift#L2767), [toolbar swipe direction](../../../CrestTests/BrowserChromeLayoutTests.swift#L2794), and [owning-window sidebar state](../../../CrestTests/BrowserChromeLayoutTests.swift#L2943).

## Applied extension assertion cleanup

[BrowserChromeWebStoreTests](../../../CrestTests/BrowserChromeWebStoreTests.swift) retains every method and scenario. Seven assertion evaluations were removed:

- Five helper-name entries in `testCompatibilityRuntimeReportsWhatItCannotHonor`: `const namespacePermissions`, `const namespaceIsDeclared`, `declaredManifest.optional_permissions`, `const invokeCallbackWithLastError`, and `const capabilityWatch`. Executable tests retain undeclared-permission rejection, optional namespace publication, callback errors on native and scoped runtimes, and abandonment/retry of capability watches.
- Two source-literal assertions for `capturesExtensionConsole = true` and `false` in `testDiagnosticsChannelForwardsConsoleOutputOnlyWhenEnabled`. The same test executes both generated runtimes, verifies the enabled warning's kind/level/source, and verifies zero forwarded reports when disabled.

The removed console comment also suggested that those literals protected distinct content-addressed resource filenames. The assertions never observed filenames. No filename-generation contract was changed or newly proven by this cleanup.

The remaining diagnostic sentinel is mixed: this review did not establish executable equivalents for every unsupported-operation warning it checks. It remains. No complete extension suite was established as redundant.

## Further candidates: inspect before deleting

These are recommendations, not changes applied in this audit.

### Retire old compiler-workaround spelling checks after runtime validation

[test_xcode_cloud_configuration.py](../../../Scripts/Tests/test_xcode_cloud_configuration.py#L294) contains `test_extension_toggle_avoids_xcode_26_setter_thunk_crash` and `test_onboarding_bindings_avoid_xcode_26_setter_thunk_crash`. They require exact Swift closure spellings for an Xcode 26 workaround. The supported toolchain is now Xcode 27, but compilation alone does not prove that toggling an extension or editing onboarding state avoids the original runtime failure. Validate those interactions on the supported toolchain, retain relevant behavior/workflow coverage, then retire the spelling checks if the workaround no longer supplies a necessary contract.

The same file's project-format/deployment-target and batch-compilation assertions deserve separate review. A supported deployment target or archive configuration can be a durable release contract even when represented as configuration text.

### Reduce website copy and CSS snapshots as a coherent update

[test_product_site.py](../../../Scripts/Tests/test_product_site.py#L31) has 24 methods behind a class setup that reads the absent `Website/site.js`. The broader Python run therefore fails before any of those methods execute. Restoring an obsolete filename solely to satisfy the tests would preserve the wrong contract.

Ten concrete candidates for retirement or consolidation into current-site checks are:

- `test_homepage_is_a_full_product_story`
- `test_arc_parity_matrix_and_carried_forward_story_are_explicit`
- `test_platform_story_portrays_each_device_directly`
- `test_feature_callouts_focus_on_visible_product_behavior`
- `test_help_center_covers_the_complete_browser_and_hidden_interactions`
- `test_help_center_navbar_blur_does_not_clip_the_mobile_flyout`
- `test_migration_story_shows_the_real_mac_review_flow`
- `test_homepage_calls_out_arc_inspiration_and_independence`
- `test_customization_uses_current_cross_platform_controls`
- `test_customization_media_stays_inside_the_mobile_viewport`

These heavily pin editorial copy, historical narrative, or CSS spellings. Keep a small current-site contract covering download/support/privacy destinations, local asset and link integrity, canonical metadata, published help integrity, and absence of build-machine paths. Verify mobile clipping through rendered interaction/layout checks when it changes; CSS substring presence cannot establish viewport behavior. No website tests were deleted in this tranche because their shared setup and remaining contracts require coordinated repair.

### Resolve the force-unwrap gate's intended policy

[test_swift_force_unwrap_policy.py](../../../Scripts/Tests/test_swift_force_unwrap_policy.py) uses a broad source regex that flags contexts including implicitly unwrapped WebKit delegate parameters and established AppKit constants. This audit's failure is evidence that its syntactic approximation does not match its intended policy. Choose a narrower, demonstrably useful rule with representative inputs, or explicitly retire this heuristic and enforce the desired rule through review/tooling. Do not delete it merely to obtain a green run. It remains unchanged; see [validation](validation.md).

### Prefer mounted interaction coverage to unmounted body smoke tests

The retained settings suite emitted runtime warnings for reading SwiftUI `State` outside an installed view. These tests may demonstrate that a body can be constructed, but they do not establish live bindings, focus, or rendered interaction. Review these mixed composition tests as a group: retain important model/capability assertions and validate essential presentation through a mounted host or direct app interaction. Avoid adding more `body != nil` assertions as substitutes for behavior. No additional settings tests were removed on this evidence alone.

### Run each repository gate once per validation path

The current-repository scan in [test_repository_guardrails.py](../../../Scripts/Tests/test_repository_guardrails.py#L77) and the corresponding scan in [test_vertical_feature_contract.py](../../../Scripts/Tests/test_vertical_feature_contract.py#L73) overlap their standalone command-line entry points. Keep synthetic valid/invalid fixtures, exception handling, and preview checks. Remove duplicate current-repository invocation only after the actual CI/runner calls each required gate once; the audit found gaps in automated gate execution, so removing coverage first would weaken enforcement.

### Replace mixed extension syntax tests at the same boundary

[BrowserExtensionWebPageRuntimeBridgeTests](../../../CrestTests/BrowserExtensionWebPageRuntimeBridgeTests.swift#L446) checks installation count, document-start injection, all-frame behavior, and handler lifetime alongside literal script contents. Direct source-helper tests do not prove that `install(...)` forwards arguments. Evaluate the installed `WKUserScript.source` with the existing JavaScriptCore fixture before removing its remaining literal checks.

Chrome and Mozilla store bridge sentinels also mix copy/selector spelling with trusted-origin and install-routing requirements. Consolidate into existing DOM fixtures that exercise those same boundaries before deleting entire tests. Vendor-byte integrity checks and the two [published compatibility-matrix parity tests](../../../CrestTests/BrowserExtensionAPICompatibilityMatrixDocumentationTests.swift) remain meaningful contracts.

## Permanent coverage to preserve

| Contract | Representative existing owners |
| --- | --- |
| Shared browsing and session transitions | [BrowserStoreTests](../../../CrestTests/BrowserStoreTests.swift), [BrowserSessionTests](../../../CrestTests/BrowserSessionTests.swift), [BrowserSplitGroupSessionTests](../../../CrestTests/BrowserSplitGroupSessionTests.swift) |
| Persistence, migration, import, and sync | [BrowserSyncTests](../../../CrestTests/BrowserSyncTests.swift), [BrowserCloudRecordCodecTests](../../../CrestTests/BrowserCloudRecordCodecTests.swift), [BrowserPortableArchiveTests](../../../CrestTests/BrowserPortableArchiveTests.swift), [MobileBrowserPortableArchiveTests](../../../CrestMobileTests/MobileBrowserPortableArchiveTests.swift) |
| Credentials, profile separation, authorization | [BrowserCredentialMessageRoutingTests](../../../CrestTests/BrowserCredentialMessageRoutingTests.swift), [BrowserProfileIsolationTests](../../../CrestTests/BrowserProfileIsolationTests.swift), [MobileBrowserProfileIsolationTests](../../../CrestMobileTests/MobileBrowserProfileIsolationTests.swift) |
| Page ownership, restoration, process recovery | [BrowserPagePoolTests](../../../CrestTests/BrowserPagePoolTests.swift), [BrowserProcessRecoveryTests](../../../CrestTests/BrowserProcessRecoveryTests.swift), [MobileBrowserPageStoreTests](../../../CrestMobileTests/MobileBrowserPageStoreTests.swift), [MobileBrowserPageRecoveryTests](../../../CrestMobileTests/MobileBrowserPageRecoveryTests.swift) |
| Extension behavior and compatibility | Executed JavaScript/DOM/native bridge cases, permission denial and grant, namespace/event identity, callback/promise behavior, signed-source integrity, sandbox isolation, tab identity, update rollback, and restoration; see [extension audit](extensions.md) |
| Release and architecture enforcement | [Release workflow](../../../Scripts/Tests/test_release_workflow.py), [publication recovery](../../../Scripts/Tests/test_release_publication_recovery.py), synthetic repository and vertical-feature guardrail fixtures |

Related macOS and iOS tests are not duplicates merely because both exercise browsing. Keep separate coverage when WebKit adapters, scene ownership, input conversion, or persistence behavior differ. In particular, retain mobile shortcut conversion/alias coverage and expensive failure-path regressions whose states are not reproduced by a happy-path smoke test.

For future fixes, temporary tests, probes, fixtures, and diagnostic harnesses may help establish the issue. Before handoff, remove temporary artifacts and obsolete checks. Retain a permanent regression only when it protects an important behavior not adequately covered elsewhere. Identify the retained protection or obsolete requirement before removing a permanent test, and run the affected surviving tests. This policy is recorded in the local repository instructions; it does not authorize blanket deletion of old or bug-derived tests.

## Validation of the applied cleanup

- The four affected Swift suites (`BrowserShortcutTests`, `BrowserSidebarInteractionPolicyTests`, `BrowserSettingsPaneTests`, and `BrowserChromeLayoutTests`) plus six selected extension methods ran successfully: **221 tests, zero failures**, 7.151 seconds reported for the selected suite. This is one run; it must not be summed with earlier overlapping audit runs as unique coverage.
- `python3 -m unittest discover -s Scripts/Tests -p test_repository_guardrails.py`: **11 tests, zero failures**, 2.636 seconds.
- Diff inspection verifies that the five method-cleanup files contain only the intended deletions; the extension file contains only the separately described assertion trim. No production behavior was changed.
- The broader pre-existing Python failures and the stale iOS palette expectation remain documented in [validation](validation.md). The focused cleanup run does not imply that the full repository suite passes.
