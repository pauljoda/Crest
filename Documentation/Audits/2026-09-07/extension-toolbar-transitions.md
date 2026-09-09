# Extension toolbar transitions and loading — 9 September 2026

The desktop address band used the committed Space to decide whether to include the extension strip. Its height changed by **47 points** when selection committed. That resized the native pager, whose resize handling cancels motion. The moving page also chose its pinned-grid inset independently. This produced the reported vertical snap.

The address band now has a constant height. The native pager owns the complete address-to-content inset: 48 points with a toolbar, 9 points with pinned tabs and no toolbar, and 1 point with neither. It interpolates that inset with the same fractional Space coordinate, 320 ms settlement curve, and interruption handling as horizontal paging. Retained toolbar views use that coordinate for their vertical position and opacity. Their bottom edge meets the tab content's top edge; the strip emerges from beneath the fixed address field without drawing over the pinned tiles.

If an extension finishes loading during a swipe, its updated layout and controls wait for that swipe to settle. The new inset then uses the existing curve. Its additive vertical correction can continue through another horizontal gesture. Access changes redact the retained controls immediately. Toolbar retention is bounded to four roots, and progress does not rebuild their SwiftUI content.

## Loading work

Toolbar presence no longer constructs full action models. Rendering pinned controls reads only pinned action presentation data; commands and native context menus remain available through the existing invocation path. The strip also computes its presented actions once per body evaluation.

The loading trace identified synchronous package staging on the main actor. The staging port is now asynchronous for unpacked, Chrome, Firefox, and local packages. A worker owns validation/copying/writing; it receives only immutable input and the destination root and creates its own FileManager. Registry changes, permissions, WebKit objects, and publication remain on the owning actor. Cancellation discards an unpublished staged package. Existing replacement and failure-cleanup behavior remains covered.

WebKit still requires its runtime APIs on the main actor. Apple documents [WKWebExtensionContext](https://developer.apple.com/documentation/webkit/wkwebextensioncontext) as `@MainActor`; [loading a context](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller/load(_:)) starts background content and injection. This change does not move those objects onto an unsupported executor or shorten extension readiness checks.

## Measurements

Artifacts are under `/private/tmp/crest-toolbar-progress-20260909`. Captures contain only the isolated test window. Time Profiler recorded 15-second intervals; the temporary main-actor sampler requested an 8 ms interval for approximately 23 seconds. These are Debug-build diagnostics, not a display FPS benchmark or a new physical-trackpad acceptance capture.

| Capture | Observation |
| --- | --- |
| `baseline` | Pager top changed from 85 to 132 points, height from 665 to 618, when toolbar presence changed. |
| `vertical2`, `gesture2` | Outer pager frame stayed at top 84, height 666. Actual generated scroll events exercised slow swipes and interrupted reversals. |
| `loading1` | Unpacked Dark Reader staging accounted for 33 ms of sampled main-thread CPU. |
| `install-final` | Staging accounted for 40 ms on a worker, with no staging samples on main. Native WebKit load accounted for 39 ms on main; first action/artwork retrieval took 5.27 ms elapsed. |
| `restore-final` | Fresh-context restoration took 866 ms elapsed, predominantly asynchronous waiting; native WebKit load accounted for 22 ms of main CPU. First action retrieval took 0.15 ms elapsed. |
| `gesture-separated` | Final scroll-event capture verifies the toolbar emerges above the pinned grid instead of fading over it. |

The fixture used Dark Reader 4.9.129 and the production compatibility preparer for the final installation/restoration captures. The earlier unpacked baseline used the identity preparer, so total startup durations are not a matched before/after performance comparison. Staging samples establish the executor change directly.

The main-actor sampler's largest observed gaps were 73 ms during installation and 56 ms during restoration. Those include scheduling, native startup, and instrumentation; they must not be described as zero stalls or as dropped display frames. Cached icon reads were approximately 0.002–0.005 ms. Native startup remains a cost, while already-running compositor animation continues independently.

## Validation and retention

The existing native-decoration contract now checks horizontal position, tab-list vertical position, toolbar position/opacity, picker, and background against one compositor timeline while withholding main-thread progress callbacks for 90 ms. It covers an interrupted continuation through a third Space, bounded retention, and an inset change arriving during settlement.

The package round-trip test now exercises the asynchronous staging entry point and cancellation cleanup. Existing installation tests cover failed-load cleanup and replacement preserving pins and shortcuts. Temporary capture code and probes are kept in the artifact directory and removed from the repository.

- Broad affected Mac contracts: 229 tests, four existing integration skips, zero failures (`contracts1.xcresult`).
- After async cancellation and deferred-layout coverage: 147 Mac tests, zero failures (`final-contracts.xcresult`).
- Final toolbar separation: 133 Mac layout/gesture tests, zero failures (`separated-contracts.xcresult`, repeated after excluding zero-size host initialization in `sizing-contracts.xcresult`). These overlap the earlier runs and are not additive coverage counts.
- Mobile build/navigation/access contracts: 149 tests, zero failures (`mobile-contracts.xcresult`).
- Live Firefox Dark Reader popup across persistent restoration: passed in 49.9 seconds (`darkreader-compatibility.xcresult`), including the idle restoration interval.
- Final optimized macOS Performance Soak build: succeeded (`release-sizing-build.log`).
- Changed-file Swift formatting, version/release catalog validation, and whitespace checks: passed.

Version: **0.5.88**. The retained tests replace the obsolete split address/pinned inset assertions; no temporary capture fixtures or diagnostic test methods remain in the repository.

The optimized demo is running from `/private/tmp/crest-toolbar-progress-20260909/HandoffProducts/Crest Performance Soak.app` with the isolated 24-tab-per-Space fixture. Binary UUID: `C1B7942A-F9A1-3E5F-8E48-53A947E757DA`; SHA-256: `66b64b1fa89c54002c0af94a8776b001d6d1bc081e40e5892aed2d0b294ce20e`. The recorded toolbar fixture is separate from this regular demo.
