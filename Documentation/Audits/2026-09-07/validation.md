# Validation evidence

Revision: `457ac1d2c9bc78011e595664053f24df50ae2249`. Runs occurred September 7, 2026 with Xcode 27.0 beta (`27A5252f`), Swift 6 settings, and Xcode's bundled Python 3.9. The iOS destination was a newly created, task-owned iPhone 17 Pro Simulator, iOS 27.0 (`24A5380i`). All application launches used `CREST_ISOLATED_SESSION=1`; the installed user profile was not used for validation. Production sources remained unchanged throughout. This section records the initial baseline; the [Mac measurement pass](measurements.md) adds an isolated optimized build and six extension tests. [Test retention](test-retention.md) records subsequent test-only cleanup and its verification separately.

## Repository checks

Run from the repository root:

```sh
python3 Scripts/check-architecture.py
python3 Scripts/check-vertical-structure.py
Scripts/validate-identity.sh
Scripts/validate-cache-hygiene.sh
python3 Scripts/check-public-source.py
python3 Scripts/audit-licenses.py
python3 Scripts/release_note_catalog.py
Scripts/check-swift-format.sh
```

All passed. Architecture output: `Validated Crest architecture and Xcode 27 source guardrails.` The vertical check exited 0 with an empty debt ledger. License output reported one runtime Swift package, one bundled data set, 1,275 Help Center packages, and seven workflow action repositories. The release catalog validated 167 entries. Changed-file formatting reported `No changed Swift files to lint.`

The additional read-only full production lint invoked the active toolchain's `swift-format lint --strict --configuration .swift-format` with all 2,287 `.swift` paths under `CrestShared`, `CrestMac`, and `CrestMobile` as arguments. Exit: **1**, with 252 diagnostics across 38 files. No formatter write operation was run.

| Rule | Diagnostics |
| --- | ---: |
| Indentation | 160 |
| AddLines | 70 |
| UseLetInEveryBoundCaseVariable | 19 |
| LineLength | 2 |
| TrailingComma | 1 |

Per-file counts and the source-count method are retained in [metrics.json](metrics.json). These lint results describe formatting debt, not runtime defects.

## macOS tests

Initial command:

```sh
CREST_ISOLATED_SESSION=1 xcodebuild test \
  -project Crest.xcodeproj -scheme Crest -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/crest-quality-audit-derived-20260907 \
  -resultBundlePath /private/tmp/crest-quality-audit-macos-20260907.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:CrestTests/BrowserStoreTests \
  -only-testing:CrestTests/BrowserSidebarInteractionPolicyTests \
  -only-testing:CrestTests/BrowserCommandPaletteTests \
  -only-testing:CrestTests/BrowserExtensionAPICompatibilityMatrixDocumentationTests \
  -only-testing:CrestTests/BrowserExtensionStartupPipelineTests \
  -only-testing:CrestTests/BrowserFaviconPerformanceTests \
  CODE_SIGNING_ALLOWED=NO
```

Exit: **0**, `TEST SUCCEEDED`. Summary: **116 tests, 0 failures**, 7.222 seconds in the selected test suite. This duration is a test-run observation, not a Release performance benchmark.

After the iOS discrepancy, the existing shared policy test was run with the same configuration and Derived Data using `test-without-building -only-testing:CrestTests/BrowserCommandPaletteActionPolicyTests`. Exit: **0**, `TEST EXECUTE SUCCEEDED`, **1 test, 0 failures**. This brings the unique macOS tests exercised to **117**.

## iOS tests

The task-owned Simulator was created with:

```sh
xcrun simctl create 'Crest Quality Audit 2026-09-07' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0
```

It returned `C7B6F1C5-6976-418C-BDD5-B09839CD2C3D`. A future reproduction must use a new available destination rather than assume this task-owned device still exists.

```sh
CREST_ISOLATED_SESSION=1 SIMCTL_CHILD_CREST_ISOLATED_SESSION=1 xcodebuild test \
  -project Crest.xcodeproj -scheme CrestMobile -configuration Debug \
  -destination 'platform=iOS Simulator,id=C7B6F1C5-6976-418C-BDD5-B09839CD2C3D' \
  -derivedDataPath /private/tmp/crest-quality-audit-derived-20260907 \
  -resultBundlePath /private/tmp/crest-quality-audit-ios-20260907.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:CrestMobileTests/MobileBrowserRootModelTests \
  -only-testing:CrestMobileTests/MobileBrowserShortcutDefaultsTests \
  -only-testing:CrestMobileTests/MobileBrowserSidebarAccessPolicyTests \
  -only-testing:CrestMobileTests/MobileBrowserPageStoreTests \
  -only-testing:CrestMobileTests/MobileBrowserPortableArchiveTests \
  -only-testing:CrestMobileTests/MobileToolbarSwipePolicyTests \
  CODE_SIGNING_ALLOWED=NO
```

The app and test target compiled. Exit: **65**, `TEST FAILED`. XCTest reported **52 tests, five assertion failures** in 8.155 seconds. `xcresulttool get test-results summary` confirmed **51 passed tests and one failed test**, with no skipped tests.

The single failing test was [testPaletteActionsRejectStaleProfilesAndSelectExactDestinations](../../../CrestMobileTests/MobileBrowserRootModelTests.swift#L357). It expects a destination in another Space/profile to be selected at line 375, followed by four assertions on the resulting selection/page. The first rejection explains all five failures.

The current shared [BrowserCommandPaletteActionPolicy.target](../../../CrestShared/Features/Chrome/Components/BrowserCommandPalette/Services/BrowserCommandPaletteActionPolicy.swift#L22) requires the source and destination to share Space and profile. The existing [shared policy test](../../../CrestTests/BrowserCommandPaletteActionPolicyTests.swift#L31) explicitly expects rejection of a different Space and passed in this audit. Commit `aac042880` introduced the restriction on August 25 and removed cross-Space palette results; the mobile success expectation dates from August 15.

**Classification: stale mobile test expectation.** A focused `test-without-building` rerun of that single mobile test reproduced the same five assertions in 0.084 seconds. The test does not reach the expected destination-page creation. Simulator WebKit/DNS console noise does not explain this failure. Keep the shared Space boundary and update the mobile fixture/expectations to cover same-Space success plus cross-Space rejection.

The focused rerun entered a long Simulator diagnostics collection after reporting its failure; that task-owned diagnostic collection was interrupted after the assertion evidence was captured. The initial 52-test run has a complete result bundle and definitive exit status.

## Python suite

```sh
python3 -m unittest discover -s Scripts/Tests -p 'test_*.py'
```

Exit: **1**. Summary: **145 tests in 42.141 seconds; one failure and one class-setup error**.

- [ProductSiteTests.setUpClass](../../../Scripts/Tests/test_product_site.py#L31) raises `FileNotFoundError` reading `Website/site.js`, which is absent at the audited revision. The same suite still contains expectations for an old website domain. Update the suite around the current site's behavior and assets rather than restore an obsolete filename merely to satisfy it.
- [SwiftForceUnwrapPolicyTests](../../../Scripts/Tests/test_swift_force_unwrap_policy.py#L11) uses a text regex that reports 15 lines. Four are `WKNavigation!` delegate parameter declarations, nine convert known AppKit function-key constants, one is protected by a nil guard, and one constructs an isolated UserDefaults suite. The blanket result does not establish 15 crash paths. Reconcile the checker with the intended high-confidence contract and review actual forced operations in context; do not blanket-suppress the check or alter platform delegate signatures solely to satisfy a regex.

## Compiler diagnostics to address locally

Production actor-isolation warnings from the fresh Debug compilations:

| Platform | Location | Diagnostic |
| --- | --- | --- |
| Both | [BrowserExtensionContextObserver.swift:67](https://github.com/pauljoda/Crest/blob/457ac1d2c9bc78011e595664053f24df50ae2249/CrestShared/Infrastructure/BrowserExtensions/Controller/BrowserExtensionContextObserver.swift#L67) | Main-actor static `contextIdentifierKey` referenced from a Sendable closure |
| macOS | [BrowserSplitCardView.swift:78](../../../CrestMac/Features/SplitView/Components/BrowserSplitCardView.swift#L78) | Main-actor static `coordinateSpace` referenced from a Sendable closure |
| macOS | [BrowserSplitPageSurface.swift:90](../../../CrestMac/Features/SplitView/Components/BrowserSplitPageSurface.swift#L90) | Same coordinate-space isolation warning |
| iOS | [BrowserTransientCardArrangement+Device.swift:11](../../../CrestMobile/Features/TransientBrowsing/Support/BrowserTransientCardArrangement+Device.swift#L11) | Two warnings for `UIDevice.current` and `userInterfaceIdiom` read from a nonisolated context |

Three warning occurrences per platform; the shared one appears in both builds. Test-only deprecation, unused-value, and sendable-capture warnings also appeared. No claim of a warning-free baseline is made. Respect the system API's actor isolation and capture immutable values at the appropriate boundary rather than suppressing concurrency checking globally.

## Limits and reproducibility

The audit executed focused contract suites, not all 272 Swift test files. The initial pass did not run the full `Scripts/validate.sh`, Release builds, physical-device performance traces, signing-dependent integrations, or live external-extension account workflows. The later optimized Mac capture and exact Firefox package test are documented in [measurements](measurements.md); neither covers account workflows or the full extension matrix. The website was inspected through its source and existing checks; no fresh Help Center npm install/build was needed for this architecture audit. The Periphery binary was unavailable, so unused-code conclusions are limited to source review.

Performance recommendations identify source-backed work patterns and experiments; later Mac measurements are separately labeled. Debug XCTest durations are not evidence of shipping latency, battery impact, or a measured speedup. New performance budgets should come from reproducible optimized builds and representative library sizes.

Task-owned build products, diagnostic bundles, and the temporary Simulator are disposable. Compact logs and extracted result summaries are retained outside the repository; this file preserves the commands and outcomes needed to review or repeat the audit without committing large binary artifacts.

## Final test-retention verification

After the 11-method and seven-assertion cleanup, the affected macOS suites and retained extension contracts were rebuilt and run:

```sh
CREST_ISOLATED_SESSION=1 TEST_RUNNER_CREST_ISOLATED_SESSION=1 \
xcodebuild test -project Crest.xcodeproj -scheme Crest -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$CREST_AUDIT_DIR/TestData" \
  -resultBundlePath "$CREST_AUDIT_DIR/test-retention.xcresult" \
  -parallel-testing-enabled NO \
  -only-testing:CrestTests/BrowserShortcutTests \
  -only-testing:CrestTests/BrowserSidebarInteractionPolicyTests \
  -only-testing:CrestTests/BrowserSettingsPaneTests \
  -only-testing:CrestTests/BrowserChromeLayoutTests \
  -only-testing:CrestTests/BrowserChromeWebStoreTests/testCompatibilityRuntimeReportsWhatItCannotHonor \
  -only-testing:CrestTests/BrowserChromeWebStoreTests/testAnUndeclaredPermissionKeepsItsNamespaceOffTheCompatibilityLayer \
  -only-testing:CrestTests/BrowserChromeWebStoreTests/testAnOptionalPermissionStillPublishesItsNamespace \
  -only-testing:CrestTests/BrowserChromeWebStoreTests/testWorkerCallbackErrorsRemainVisibleOnNativeAndScopedRuntime \
  -only-testing:CrestTests/BrowserChromeWebStoreTests/testAnAbandonedCapabilityWatchRetriesAfterAFreshListener \
  -only-testing:CrestTests/BrowserChromeWebStoreTests/testDiagnosticsChannelForwardsConsoleOutputOnlyWhenEnabled \
  CODE_SIGNING_ALLOWED=NO

python3 -m unittest discover -s Scripts/Tests -p test_repository_guardrails.py
Scripts/check-swift-format.sh
python3 Scripts/check-architecture.py
python3 Scripts/check-public-source.py
git diff --check
```

All commands exited 0. XCTest reported **221 tests, zero failures**, 7.151 seconds for the selected suite; `xcresulttool` confirmed 221 passed and no skipped tests. Python reported **11 tests, zero failures**, 2.636 seconds. Changed-file formatting validated five Swift files. The settings tests emitted warnings about reading SwiftUI State outside a mounted view; their implications are recorded in [test retention](test-retention.md). The broader historical iOS/Python failures above remain unresolved; passing this affected selection is not a claim that the entire repository suite is green.

The repository's ignored local `AGENTS.md` convention was retained. The canonical local repository instructions and the audit worktree copy now require removing disposable diagnostic tests/probes, retaining important unique behavioral regressions, and identifying retained protection before deleting permanent tests. No version or release catalog was changed: this handoff contains audit documentation, local instructions, and test-only deletions, with no app-code commit.
