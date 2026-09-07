# macOS performance baseline

Reviewed production revision: `457ac1d2c9bc78011e595664053f24df50ae2249`, September 7, 2026.

**A completed optimized-build trace recorded a 267.45 ms main-thread microhang during repeated warm Space switching.** Sampled stacks include SwiftUI/AttributeGraph work, folder and tab-row presentation, Space-change synchronization, and extension-sidebar state reconciliation. This supports prioritizing the narrow selection and presentation work in the [implementation plan](implementation-plan.md). It does not establish one cause for the entire pause, per-switch latency, an animation-hitch rate, or a measured improvement.

## Environment and isolation

| Item | Recorded setup |
| --- | --- |
| Hardware | MacBook Pro, Apple M2 Max, 32 GiB memory |
| OS | macOS 27.0 beta, build `26A5421a` |
| Toolchain | Xcode 27.0 beta / xctrace `27A5252f`; Swift 6 |
| Application | `Crest Performance Soak`, bundle ID `com.pauldavis.crest.performance-soak` |
| Build | Release, Swift `-O`, `CREST_PERFORMANCE_HARNESS`; no production source changes |
| Signing | Local ad hoc signing, explicit `com.apple.security.get-task-allow = true`, hardened runtime disabled for this profiling bundle |
| Session | Isolated/reset fixture, in-memory credentials, local loopback fixture server; normal installed profile untouched |
| Library | Six Spaces, 24 tabs, eight folders, and 96 history entries per Space; 144 fixture tabs total |
| Web content | One explicitly selected/loaded tab per Space; six distinct WebContent PIDs logged |
| Extensions | None installed in the Space-switching fixture |

The first Release build with normal project entitlements failed provisioning: the available wildcard profile lacked Push Notifications and the required iCloud capabilities/container. The successful build used the task-specific signing overrides above. It is an optimized local profiling build, not a distribution-signed release, and does not validate shipping cloud/push entitlements. `release-local-build.log` records `-O` and `BUILD SUCCEEDED`; production actor-isolation warnings remained, as described in [validation.md](validation.md).

The [heavy fixture](../../../CrestShared/Application/BrowserStore/Fixtures/BrowserPerformanceSoakFixture.swift#L57) uses the same teal branding and disables content blocking in each Space. Every third tab is saved into a folder; the remainder are current tabs. Before recording, automation selected each Space with Control+1…6 and then explicitly selected its first tab with Command+1. `warmup.json` records titles `Perf 1 · 82`, `Perf 25`, `Perf 49`, `Perf 73`, `Perf 97`, and `Perf 121` and one local document request for each.

Explicit loading matters: [unloaded Space entry intentionally presents Start Page](space-switching.md). Cycling fresh fixture Spaces alone would not measure warm resident-WebKit handoffs. The retained `space-fixture.png` and accessibility/window-title checks confirm the fixture presentation; a still screenshot is not evidence of gesture smoothness.

## Completed capture and results

The usable capture is `space-time.trace`, Time Profiler run 1, from **16:52:34.728 to 16:52:47.646 CDT**. The recorder requested 12 seconds, completed successfully, and saved a **12.918348-second** trace, approximately **28 MiB** on disk.

After the recorder announced readiness, process-scoped System Events automation sent **12 alternating Control+3 / Control+4 requests**, with a nominal 0.5-second delay between them. The automation's start-to-finish span was **6.262054 seconds**; the final window title was `Perf 73`. These are input-scheduling observations, not 12 measured completion intervals. `time-switches.json` does not timestamp each displayed frame or confirm each intermediate presentation separately.

| Result | Observation | Interpretation |
| --- | ---: | --- |
| Time Profiler samples | 6,293 samples, each weighted 1 ms | 6,293 ms sampled weight across the application threads over the whole capture; not elapsed interaction latency |
| Main-thread samples | 5,765 | Main thread accounts for most sampled application work |
| Potential-hang lane | One `Microhang`, 267.45 ms | A substantial main-thread responsiveness interval was recorded |
| Microhang position | 1,792.84–2,060.29 ms after trace start | Within the period of issued switch requests; no precise input-to-frame boundary is available |
| Main samples inside that interval | 242, of 250 total samples in the interval | Sampled main-thread running coverage is 90.6% of the 267.45 ms interval; consistent with substantial running work rather than only waiting |

The hottest named leaf symbols in the exported Time Profiler analysis include:

| Leaf symbol | Sampled weight over the entire trace |
| --- | ---: |
| `AG::Graph::UpdateStack::update()` | 428 ms / 428 samples |
| `AG::Graph::propagate_dirty(AG::AttributeID)` | 392 ms / 392 samples |
| `AG::Subgraph::update(unsigned int)` | 147 ms / 147 samples |

These are sampling estimates for those leaf symbols, not SwiftUI body timings or costs assigned to one switch. Other weight appears in deduplicated symbols, reference counting, memory movement, metadata lookup, and allocation. Optimized inlining and symbol deduplication limit attribution.

An additional stack pass counted each application symbol at most once per sampled main-thread stack:

| Application frame | Inclusive stack occurrences, whole trace |
| --- | ---: |
| `BrowserFolderGroupSurface.body` | 73 |
| `BrowserFolderGroup.body` | 59 |
| `BrowserRootModel.synchronizeAfterSpaceChange()` | 57 |
| `BrowserExtensionSidebarHost.reconcile()` / store `reconcilePresentation` / `optionsRevision.modify` | 56 each, along overlapping call paths |
| `BrowserSidebarTabRowSurface.body(content:)` | 51 |

**These inclusive counts overlap and must not be added as durations or shares of the pause.** Within the microhang, the root/extension-sidebar path appears in six main-thread samples, and folder-group and WebKit host-attachment paths appear in three each. That is insufficient to attribute the full 267.45 ms to any one of them.

The extension-sidebar path is Crest host bookkeeping even in this extension-free fixture. [The host](../../../CrestMac/Features/ExtensionSidebar/Services/BrowserExtensionSidebarHost.swift#L46) updates outgoing/incoming Space visibility; [the store](../../../CrestShared/Application/BrowserExtensionServices/Sidebar/BrowserExtensionSidebarStore.swift#L255) increments `optionsRevision` when that visibility changes. This is a concrete observation boundary to investigate alongside row/folder dependencies. It is not evidence that a third-party extension caused this capture's pause. The [Space call-chain report](space-switching.md) supplies the wider source analysis.

## Capture failures and attribution limits

The richer captures did not produce usable results:

| Attempt | Outcome |
| --- | --- |
| SwiftUI template, 30-second recording | Failed to finalize after roughly six minutes. A retained process sample recorded xctrace's reported 16.8 GB physical footprint. The incomplete capture was removed. |
| Animation Hitches template, 20-second recording | Still finalizing after more than two minutes with roughly 9.9 GB of trace output; stopped to bound disk use. Its process sample was retained and the incomplete capture removed. |
| Time Profiler, 12-second recording | Completed with exit 0 and usable exported samples/hang data. |

The 16.8 GB figure is the profiling tool's footprint, and the 9.9 GB figure describes incomplete trace output; neither is Crest's application-memory result. A wrapper message saying a trace was written was not treated as successful finalization.

The completed trace lacks Animation Hitches, SwiftUI view-update, and SwiftUI Cause & Effect lanes. Extracted Crest signpost intervals/events were empty (`space-signposts.json`). Existing signposts in source do not supply missing evidence in this capture. Consequently, there is **no measured end-to-end switch interval, p95/p99 switch latency, dropped-frame count, render-server cost, or proven dependency cause** here. Do not divide aggregate sample weight by 12 and label the result switch latency.

Additional limits:

- The original run is one short capture on a beta OS/toolchain, after expensive profiler attempts. There was no matched idle control, clean restart between every capture, or controlled thermal/power comparison.
- Space 1's loaded page continued its [750 ms title/history mutation timer](../../../CrestTestFixtures/performance.html#L76) while Spaces 3 and 4 were switched. Some sampled session work may reflect background updates; repeat with mutation disabled and an idle control to isolate it.
- All Spaces used the same branding. The capture cannot assess a contrasting-theme color wipe, intermediate contrast, or material/texture transition cost.
- The original interaction was programmatic keyboard selection. The follow-up below adds Computer Use and accessibility observations; physical trackpad/touch progress, reversal, momentum, and animated visual continuity remain unvalidated.
- No app/WebContent memory delta, cold-loading comparison, pressure test, long-session result, 200/500-tab scale run, multiwindow run, or extension-enabled Space-switching comparison was completed in this trace.

## Computer Use follow-up

The installed Computer Use plugin was accessed through its configured persistent JavaScript runtime after the user approved access to the isolated app for this session. No plugin configuration or persistent app permission was changed. The original capture above preceded this connection; its System Events procedure is retained as historical reproduction evidence. Subsequent native UI actions used Computer Use.

A fresh isolated launch used the same optimized executable and fixture. Computer Use selected and explicitly loaded the first tab in all six Spaces, verifying the corresponding `Perf 1/25/49/73/97/121` window titles. It then issued six alternating Control+3/Control+4 requests, reading the actual accessibility state after every request. All six observations showed the requested `Perf 49` or `Perf 73` destination. A plugin screenshot additionally showed the selected page visible with load count 1.

`space-cua.trace` is a second completed Time Profiler recording. The requested duration was 20 seconds; the recorded duration was **21.313435 seconds**. The first two requests began before the recorded start: four requests were issued within the trace and one earlier request was still awaiting observation at its start. The six-state UI verification and recorded timing coverage therefore differ. It contains 5,854 weighted CPU samples, 5,504 on the main thread, and six potential-hang intervals totaling approximately 4.256 seconds; the largest is approximately 1.086 seconds. These results describe **switching with repeated Computer Use accessibility inspection**, not normal unaided switching latency.

The extra stack analysis found `AccessibilityNode.updateFocus` in 2,520 main-thread stacks, `AccessibilityNode.updateFocusResponder` in 2,519, and `BrowserSpaceSwitcherCompactPicker.revealSelection` in 229. Root selection/extension-sidebar reconciliation appeared in 67. These are overlapping inclusive occurrences. They establish significant accessibility/focus work in this workload; they do not prove that all additional cost belongs to Crest, that ordinary gestures take a second, or that VoiceOver has the same behavior. Pair future captures with and without frequent AX reads, and examine selected-picker focus/reveal work while preserving accessibility.

Computer Use's six request-to-observation spans include its automatic settling and accessibility capture. They must not become popup/switch response-time metrics. Neither this capture nor the first provides per-frame hitch data or a before/after optimization comparison.

A separate horizontal input probe targeted the current `space-pager` accessibility element. One `scroll(right, 1 page)` call left Space 4 selected. Invoking its exposed **Next Space** action then advanced exactly to Space 5 and displayed resident `Perf 97` with load count 1. This verifies the semantic adjacent-Space path and an automation limitation; it does **not** reproduce physical trackpad gesture phases or momentum. The requested one-gesture/one-step behavior still needs actual trackpad and horizontal-wheel validation during implementation.

The supported CUA procedure selects the isolated app with `cua.getApp("com.pauldavis.crest.performance-soak")`, uses `pressKey("ctrl+3")` / `pressKey("ctrl+4")`, and inspects `getAXState()` after actions. Use fresh observed element indices for `scroll` or `performSecondaryAction`; this audit's index is not a stable API. Record with Time Profiler concurrently. A production acceptance capture should use stage signposts and presented frames to separate application latency from observation latency.

## Separate extension compatibility baseline

The exact Firefox **Dark Reader 4.9.129**, Manifest V2 background-page package, was tested in an isolated Debug test host. Its archive SHA-256 was `f4f047fe08e420b6d29617738ea00a7b784892b2262b7e6f38dd09b8ee958a44`. This is separate from the extension-free Release Space fixture.

`extension-test-summary.json` reports **six passed, zero failed, zero skipped**: the live Firefox popup/persistent-restoration scenario and five background-warm-up tests. The live test passed in 56.110 seconds, including a deliberate 45-second idle. The helper waits four seconds before starting its readiness timer; that duration and a near-zero later readiness value cannot establish fast first-click recovery. A runtime main-thread warning lacked an attributed cause. See [extensions.md](extensions.md) for commands, exact behavior, and matrix limits; this pass does not certify MV3 worker recovery, real-account flows, or the full compatibility matrix.

## Reproduction and retained evidence

Keep a new task directory and the dedicated bundle identity. Create `Profile.entitlements` containing only the Boolean `com.apple.security.get-task-allow = true`, then use the effective build command below from the repository root. `CREST_AUDIT_DIR` must point to that task directory.

```sh
xcodebuild -project Crest.xcodeproj -scheme Crest -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$CREST_AUDIT_DIR/DerivedData" \
  PRODUCT_BUNDLE_IDENTIFIER=com.pauldavis.crest.performance-soak \
  'PRODUCT_NAME=Crest Performance Soak' \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CREST_PERFORMANCE_HARNESS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  CODE_SIGN_ENTITLEMENTS="$CREST_AUDIT_DIR/Profile.entitlements" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_HARDENED_RUNTIME=NO \
  PROVISIONING_PROFILE_SPECIFIER= build
```

Start the existing `FixtureServer` from [reference_browser_corpus.py](../../../Scripts/reference_browser_corpus.py), then launch the verified performance executable using [the soak launch environment](../../../Scripts/crest_release_soak.py#L827): `CREST_RESET_SESSION=1`, `CREST_USE_IN_MEMORY_CREDENTIALS=1`, the local `CREST_PERFORMANCE_BASE_URL`, `CREST_PERFORMANCE_TAB_COUNT=24`, and a fresh `CREST_PERFORMANCE_RUN_ID`. Add `CREST_ISOLATED_SESSION=1` and `CREST_PERFORMANCE_HEAVY_SESSION=1`. Explicitly select/load one tab in each Space and verify its title before warm measurement.

Record using the newly launched process ID, then issue the input sequence after recorder readiness:

```sh
xctrace record --template 'Time Profiler' --attach "$CREST_AUDIT_PID" \
  --time-limit 12s --output "$CREST_AUDIT_DIR/space-time.trace"
```

In a separate process, target only the isolated app:

```applescript
tell application "System Events" to tell process "Crest Performance Soak"
    set frontmost to true
    repeat 6 times
        keystroke "3" using {control down}
        delay 0.5
        keystroke "4" using {control down}
        delay 0.5
    end repeat
    return name of window 1
end tell
```

The external audit record retains `release-build.log`, `release-local-build.log`, `Profile.entitlements`, `warmup.json`, `time-switches.json`, `record-time.log`, `space-time.trace`, `space-time-analysis.json`, `trace-callers.json`, `space-signposts.json`, `space-fixture.png`, and `extension-test-summary.json`, plus diagnostic process samples and relevant logs. The follow-up additionally retains `space-cua.trace`, `space-cua-analysis.json`, `cua-trace-callers.json`, `cua-switches.json`, and a plugin screenshot. Large diagnostic artifacts remain outside the source tree. Temporary launch/input/profiling clients and the copied extension fixture are removed at handoff; the effective commands, input sequences, trace metadata, and result summaries preserve the evidence.

The next comparison should repeat this warm workload with an idle/background-mutation control, then capture input-to-presentation and actual frame data on representative hardware. Proposed budgets and the remaining lifecycle/gesture/memory gates are in [space-switching.md](space-switching.md) and [implementation-plan.md](implementation-plan.md); this baseline does not claim those targets are met.
