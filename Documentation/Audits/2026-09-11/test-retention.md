# Test goals and retention audit — September 11, 2026

**Latest:** the [manual UI review pass](test-retention-ui.md) records 256 further removals and current validation. Cumulative cleanup is 439 methods net and 11,906 test/fixture lines. The [earlier follow-up](test-retention-followup.md) and the counts/results below describe prior stages.

The suite mostly protects real product behavior. The main waste was concentrated in visual constants, unmounted view smoke checks, duplicated shared policies, historical website expectations, and experimental WebKit instrumentation. Some valuable tests had stale inputs or exercised the wrong product path; those were repaired rather than deleted.

This cleanup removes **95 test methods net and approximately 2,700 test lines**, excluding concurrent favicon changes. It retires two experimental Swift files and one conflicting Python heuristic. It does not establish a suite-speed improvement or a completely passing repository.

## Standard and scope

The user confirmed these goals from the [README](../../../README.md) and [architecture](../../ARCHITECTURE.md): Space isolation, dependable browsing and persistence, native platform behavior, privacy, and extension compatibility. [Repository guardrails](../../RepositoryGuardrails.md) and the [previous retention audit](../2026-09-07/test-retention.md) supply additional repository contracts.

The starting worktree was based on `6f53535b0e9081a3bb42fd62495ed763a4bc4782`, with favicon source, fixtures, tests, and project configuration already being edited. Those edits were preserved and continued changing during validation. Their test failures are reported separately; they were not removed to make this audit pass.

The [inventory](test-inventory.csv) records all **300 starting test/support files**, their method counts, disposition, goal, and retained responsibility. Review covered the method inventory and assertions across every suite, with full test-body and owning implementation inspection for removal candidates, contradictory expectations, failures, and coverage overlaps. This is a contract audit, not a claim that every line of roughly 132,000 lines of test/support code was rewritten or individually proven correct.

The [method ledger](test-removals.md) names every removed or replaced method and identifies its obsolete requirement or retained protection. Counts below exclude the untracked, concurrently changing `BrowserFaviconPrivacyTests.swift`; the CSV includes that file as preserved concurrent work. Three private helpers whose names start with `test` are excluded from method counts.

| Source | Files before → after | Methods before → after | Net reduction |
| --- | ---: | ---: | ---: |
| macOS/shared Swift, excluding concurrent privacy file | 243 → 241 | 3,031 → 2,976 | 55 |
| Mobile Swift | 37 → 37 | 444 → 425 | 19 |
| Python | 18 → 17 | 168 → 147 | 21 |
| Shell harness | 1 → 1 | — | — |
| Total | 299 → 296 | 3,643 → 3,548 | 95 |

The concurrent privacy file declared five tests at intake and six during the later macOS run. Declared methods, XCTest executions, skipped methods, and assertion failures are different counts.

## Changes and retained contracts

- **Settings and chrome:** removed unmounted `.body != nil` checks, initializer/closure echoes, exact decorative sizes, colors, shadows, disclosure defaults, and presentation flags. These assertions could pass without a mounted, usable control. Kept preference mutation/persistence, selected-Space bindings, credential filtering and privacy warnings, native command routing, window/control identity, responder handling, and geometry/accessibility constraints. Builds still type-check the view bodies; they do not replace mounted UI validation.
- **Adaptive input:** consolidated 19 sidebar metric/profile cases into a four-combination touch/hover matrix and minimum touch-target/content-growth checks. Retained reveal policy, Dynamic Type, drag/drop ownership, matched anchors, and platform interaction tests. A trackpad must not remove finger-sized targets from a touch device.
- **Settings capability:** replaced the misleading desktop-only assertion that shortcuts were the only platform-gated destination. Desktop tests cover its complete catalog; mobile tests exclude shortcuts, extensions, and WebKit feature flags. Existing accessibility raw values remain protected because the source explicitly declares them an automation contract. Catalog order and new destinations are no longer frozen by that identity test.
- **Shared duplication:** removed mobile repetitions of the shared download ledger, response-to-download policy, reload policy, Space foreground-color policy, and archive filename. Owning shared tests remain on macOS. Native mobile download, WebKit, storage, UIKit input, scene and recovery integrations remain separate because their adapters differ.
- **Setup and navigation:** removed an identical onboarding-progress case that never supplied the seed state its name claimed to exercise, a default palette snapshot, and tests for an unshipped contextual swipe mode. The shipped cards-only swipe rule remains. The mobile sidebar test now checks the current minimum-width boundary and the existing exhaustive width sweep instead of a retired literal 579-point breakpoint.
- **WebKit investigation:** retired `BrowserExtensionBackgroundWakeExperimentTests` and `BrowserExtensionBackgroundRestartMeasurementTests`. Engine idle delays, fabricated event wakeups, and experimental unload/load counts are not shipping recovery contracts. The [worker report](../../WebKitExtensionWorkerReport.md) preserves historical findings and instructions for retrieving the instruments. Warm-up completion/error/deadline/once behavior, context restoration, permission-triggered restart, native broker rehydration, and live signed-extension integrations remain.
- **Repository tooling:** removed two Xcode 26 workaround spelling checks. Current Xcode 27 builds and retained state/extension workflow tests provide relevant coverage; exact closure text never proved that a rendered toggle avoided a runtime crash. No workaround implementation was removed. Manual mounted interaction validation of that historical compiler issue was not performed.
- **Force operations:** retired `test_swift_force_unwrap_policy.py`. Its blanket ban conflicted with the explicit `.swift-format` settings, flagged WebKit IUO delegate parameters, and missed a forced-cast probe. Its baseline 21 reports were not all false positives: they also included actual force operations. Privacy and crash-boundary tests remain; this change neither approves each force operation nor proves crash freedom.
- **Website:** replaced 24 historical marketing/CSS/file-layout checks with seven published-output contracts. They validate download/help/privacy/support destinations, local links and assets, canonical metadata, manifest icon dimensions/start route, sitemap targets, authored guide publication/legacy redirect, and absence of build-machine paths. The previous shared setup required the absent `Website/site.js`, preventing the class from running. The new checks exposed real stale domains, manifest routes, and homepage fragments; those links were fixed to the existing `crestbrowser.com` site and current sections. No marketing redesign or rendered browser-layout validation was performed.

## Valuable tests repaired

| Test area | Mismatch | Final protection |
| --- | --- | --- |
| Encrypted CloudKit branding | A changing preview fixture supplied only two of nine purportedly tested symbols and a newer render version. | Explicit fixtures round-trip all nine symbols and assert the complete decoded count and payload. |
| Forward-compatible sync | `griffin` had become supported, so it no longer represented an unknown future symbol. | Clearly unknown sentinel values and a future render version still exercise safe fallback while preserving the valid record. |
| Media-session WebKit fixtures | The first newly queued event could describe the previous playback state. | Wait for both a new event and the expected active-session state. |
| Mobile popup configuration | Expected automatic popups enabled before permission. | Assert the privacy-preserving default is disabled. |
| Popup fixtures | Native-only waiting did not establish that the unmounted document had run its scheduled attempts. | Wait for document readiness and the scripted attempts before native assertions. An intermittent missing blocked notice remains, documented below. |
| Mobile scroll preservation | The initial scroll was read before WebKit applied it. | Observe a nonzero initial scroll before testing preservation through relocking. |
| Private risky download | `startDownload(using:)` is user initiated; an ordinary executable correctly uses platform protection without the extra prompt. | Serve an executable MIME type under an image filename, verify the mismatch still prompts, and retain private Space ownership/cancellation/no-file assertions. |
| Persistent tab restoration | Isolated test hosts default to ephemeral stores, which intentionally disable disk archives. | Explicitly request persistence with fresh test profiles; private mode must override that request and archive nothing. Real history/scroll restoration and offline browsing pass with local servers. |

## Deliberately retained

Large suites are not automatically bloat. Session/store/sync permutations cover different ownership, ordering, migration, conflict, rollback, and stale-completion states. Split/drag tests protect cross-Space assignment and pointer geometry that a session-only test cannot observe. Separate native macOS and iOS adapters still need separate coverage.

Extension source reads were evaluated by what they protect. Executed generated JavaScript, vendor-byte preservation, wire values, signed-package validation, permission checks, callback/promise behavior, and native routing remain. Mixed unsupported-capability sentinels remain where executable equivalents were not established. No blanket source-string deletion was applied.

The three opt-in worker storage/broadcast diagnostics inside `BrowserExtensionControllerPoolTests` still cannot distinguish the XCTest-host problem from a product failure according to their own documentation. Their underlying persistence/messaging contracts remain important and equivalent reliable end-to-end coverage was not established, so they were retained as an explicit validation gap. They should be replaced at a working host boundary before their diagnostic scaffolding is removed.

Release/signing/publication and architecture guards protect operational contracts. Executed release preflight fixtures replace the redundant unchanged-nightly source sentinel; signing/entitlement checks and synthetic guard fixtures remain. A failing architecture guard was not disabled.

## Validation and remaining gaps

Environment: Xcode 27.0 (`27A266a`), macOS arm64, and a dedicated iPhone 17 Pro simulator with the installed iOS 27 runtime. Swift runs used `CREST_ISOLATED_SESSION=1` and Derived Data outside the repository. The audit-owned simulator and temporary investigation scripts were removed after validation. Logs/result bundles are under `/tmp/crest-test-audit`; counts from overlapping selections must not be summed as unique coverage.

| Run | Observed result |
| --- | --- |
| Starting macOS suite, `mac-before` | 3,036 tests, 33 skipped, 11 assertion failures in five methods. |
| Starting Python discovery, `python-before` | 144 methods executed, two failures and one class-setup error; website's 24 methods could not execute. |
| macOS after main cleanup, `mac-after` | 2,981 tests, 29 skipped, two failures: concurrent favicon privacy capture and retained extension WebP conversion. All audit-edited methods executed in this run passed. This preceded the restored stable-ID assertion and explicit persistent-network setup. |
| Final settings identity and extension conversion selection, `mac-final-focused` | Three tests passed. The conversion fixture passed unchanged, so the earlier failure is intermittent, not resolved or deleted. |
| macOS with local servers, `mac-network-final` | All four previously skipped network/offline cases passed, including restored history/scroll and private no-archive behavior. The 16-test selection had five assertions fail in the intermittent blocked-popup allow/retry case; its initial blocked notice was missing. The same case passed earlier focused and full runs. No claim of stable popup validation is made. |
| Mobile full selection, `mobile-after` | All 425 methods from `CrestMobileTests` passed. Five concurrent shared favicon privacy methods contributed 15 assertion failures. XCTest logged all 430 completions, but xcodebuild did not exit and was stopped after it remained idle; this is not a successful command result. |
| Final retained mobile command, `mobile-retained` | 425 tests passed, zero failures; xcodebuild exited successfully. The separate concurrent shared favicon class was excluded from this confirmation run. |
| Python after cleanup, `python-after` | 147 tests, one retained architecture-guard failure. The seven website checks pass. |
| Cache-hygiene shell harness | Passed. |
| Final static checks | `git diff --check` and strict swift-format on all 20 audit-edited surviving Swift files passed. Website tests also passed under Xcode’s Python 3.9. |

The Python guard still reports:

1. `CrestShared/Features/Sidebar/Components/BrowserFolderGroup/Support/View+BrowserFolderHeaderLayout.swift` declares a primary `BrowserFolderHeaderDensityLayout` type in a named-extension file.
2. `CrestMac/Features/Browser/BrowserRootView/BrowserRootView.swift` previews a view that owns live `@AppStorage`.

These were present before this cleanup. They need source or explicitly documented architecture-policy resolution, not a weakened test.

The remaining opt-in gaps include current signed extension packages/popups, a signed Keychain host, real clipboard integration, interactive Picture in Picture, Safari extension host discovery, and the three worker diagnostics. Removing four retired experiments accounts for the macOS skip-count reduction from 33 to 29; it is not new executed coverage. The local-server follow-up executes four of those 29 remaining skips.

The checked-in GitHub CI workflow builds the apps and Help Center and runs selected source/release checks; it does **not** execute the Swift or Python test suites. Retained tests cannot be relied on as PR gates until an appropriate test lane is configured. No CI overhaul, commit, version bump, or release was performed by this audit.


Core reproduction commands (use a disposable simulator and an external output directory):

```sh
CREST_ISOLATED_SESSION=1 xcodebuild -project Crest.xcodeproj -scheme Crest \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/crest-validation-mac test
CREST_ISOLATED_SESSION=1 xcodebuild -project Crest.xcodeproj -scheme CrestMobile \
  -destination 'platform=iOS Simulator,id=<disposable-simulator-id>' \
  -derivedDataPath /tmp/crest-validation-mobile test
python3 -m unittest discover -s Scripts/Tests -p 'test_*.py'
Scripts/Tests/validate-cache-hygiene-tests.sh
```

For the four network cases, start `CrestTestFixtures/network-server.py --port <network-port>`
and `CrestTestFixtures/offline-server.py --port <offline-port>` in separate processes.
Forward `TEST_RUNNER_CREST_NETWORK_FIXTURE_URL=http://127.0.0.1:<network-port>/`
and `TEST_RUNNER_CREST_OFFLINE_FIXTURE_URL=http://127.0.0.1:<offline-port>/offline.html`
to xcodebuild and select `CrestTests/BrowserWebCompatibilityTests`.
The offline case stops its server deliberately; stop the other owned server afterward.
