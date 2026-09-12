# Test retention follow-up

**Latest:** the [manual UI review pass](test-retention-ui.md) supersedes this stage’s visual-test retention decisions and records current validation. The counts and results below remain the historical follow-up.

The user asked for more aggressive cleanup: settled features should not accumulate permanent tests merely because they exist, and the remaining failing scenarios could be retired. This pass applies that maintenance tradeoff while retaining focused checks where failures could lose browsing state, cross Space/authorization boundaries, or break native and extension interoperability.

**Removed another 88 test methods and 2,660 test/fixture lines.** Combined with the first pass, the cleanup removes **183 methods net and 5,361 test/fixture lines**. These totals exclude the separate favicon work. No production behavior was changed in this follow-up.

| Source | Additional methods removed | Retained declared methods, excluding concurrent favicon privacy file |
| --- | ---: | ---: |
| macOS/shared Swift | 63 | 2,913 |
| Mobile Swift | 23 | 402 |
| Python | 2 | 145 |
| Total | 88 | 3,460 |

The [inventory](test-inventory.csv) retains the initial and first-pass counts and adds `methods_after_followup` and `followup_disposition` for every starting file. The [follow-up ledger](test-removals-followup.md) names all 88 additional methods and explains their retained coverage or accepted retirement. The [first-pass report](test-retention.md) remains a historical record of that validation.

## What changed

- Removed fixed appearance, animation, route, spacing, gallery-order, copy and initializer-forwarding assertions across chrome, mobile navigation, settings, branding, sidebar, About and error pages. Native host/document survival, real command actions, useful touch targets, accessibility behavior, persistent settings, migration and Space ownership remain.
- Removed the complete address-display example, scene-ID literal, and screenshot/showcase-data suites. Those settled display/demo choices are now reviewed when changed. Browsing URL resolution, window restoration/ownership, launch isolation and real first-run/practice behavior remain tested.
- Removed mobile duplicates of the three shared reduced-motion/transparency policy tests. The macOS owning tests still execute the same functions; native mobile layout and safe-area coverage remains separate.
- Removed static Reader state/action tables while retaining payload decoding and the actual Reader bridge integration on both platforms.
- Removed the prose-wide pinned-SHA whitelist from extension documentation tests. The remaining generator comparison still checks that public capability tables match executable routing, and remains the existing tool for regenerating those tables.

## Disposition of the previously failing or unusable cases

| Scenario | Decision and remaining protection |
| --- | --- |
| Desktop blocked-popup allow/retry combined fixture | Removed. Shared policy and permission persistence/Space-scope tests remain, the mobile integration exercises the shared blocked-message/allow/new-attempt flow, and desktop WebKit cases still cover blocked/default/denied requests and adopted popup opener/close behavior. This exact desktop combined sequence is no longer a permanent gate. The intermittent missing notice is not claimed fixed. |
| Menu → WebP conversion → JPEG download demonstration | Removed. Verified menu, download and offscreen broker cases retain permission and extension/tab/Space dispatch; a focused real extension JPEG download still covers requested filenames, destination prompting and completion. Transfer tests retain moved bytes and quarantine. The combined conversion demonstration is no longer a permanent gate. |
| Three opt-in worker storage/broadcast diagnostics | Removed with their unused Swift helpers, JavaScript entry points, startup-control writes and runtime-bypass fixture branch. They were documented as unable to return in XCTest. Independent storage/Space isolation, native broker authorization and recovery, popup port/reload and multi-listener dispatch remain. A reliable equivalent of the exact worker-to-popup storage/broadcast experiment was not established; that gap is accepted rather than hidden behind permanently skipped instrumentation. |
| Live repository architecture scans inside unit tests | Removed both wrappers consistently, including the failing vertical-debt check. `Scripts/check-vertical-structure.py` and `Scripts/check-architecture.py` remain directly runnable audits, with their synthetic valid/invalid/exemption/debt tests intact. A passing Python suite no longer implies that the live repository passes those separate audits. The two previously reported source-layout/preview violations were not fixed by deleting the wrappers. |
| Concurrent favicon privacy failures | Retained. The separate favicon task reports passing focused macOS and iOS validation after fixing its loading policy. These tests cover active cookie, credential, redirect and resource boundaries. Their code was preserved. |

## Validation

Verification uses the affected surviving macOS suites plus the focused tests cited as retained protection, the mobile suite, and all Python tests. JavaScript syntax checks cover the pruned common popup fixture, and strict Swift formatting covers the 12 surviving Swift files edited in this pass. Results and commands are retained under `/tmp/crest-test-cleanup-followup`.

| Check | Result |
| --- | --- |
| Selected macOS suites | 352 executed, one opt-in clipboard test skipped, zero failures; `TEST SUCCEEDED`. The four network/offline fixtures ran against local servers. |
| Retained mobile suite | 402 executed, zero failures; `TEST SUCCEEDED` on an isolated iPhone 17 Pro simulator with iOS 27. The concurrent favicon privacy file was excluded from this run. |
| Python discovery | 145 tests passed. |
| Shared popup JavaScript | Both `background.js` and `popup.js` passed `node --check`. |
| Swift formatting | All 12 surviving Swift files edited in the follow-up passed strict formatting. |
| Project and patch | XcodeGen regenerated the project after the three additional Swift file removals; `git diff --check` passed. |

The macOS selection covers About, chrome layout, download transfer, extension capability documentation, extension controller pooling, native messaging, navigation failures and policy, page actions, Reader, settings, sidebar interactions, branding, site permissions, and WebKit compatibility. Its exact `xcodebuild` argument list is saved in `mac-command.json`. Both Swift runs used `CREST_ISOLATED_SESSION=1`; the macOS run additionally supplied `TEST_RUNNER_CREST_NETWORK_FIXTURE_URL` and `TEST_RUNNER_CREST_OFFLINE_FIXTURE_URL` for owned local fixture servers. Python ran with `python3 -m unittest discover -s Scripts/Tests -p 'test_*.py'`.

This follow-up did not rerun every macOS test. The opt-in clipboard case, retired combined scenarios, and known direct architecture-audit violations remain outside the passing results above. No speed improvement is claimed: the retained mobile loaded-page relocking test passed but took about 196 seconds in this run. It protects actual form, scroll and navigation-history survival across repeated locking, beyond the simpler resident-object identity check. Temporary cleanup scripts, diagnostic probes, fixture server processes and the dedicated simulator were removed after validation; logs and result bundles remain available.
