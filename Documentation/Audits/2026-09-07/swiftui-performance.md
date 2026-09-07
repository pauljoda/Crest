# Crest SwiftUI performance audit

Audited revision: `457ac1d2`. The source establishes work and dependency patterns; measured attribution and remaining gaps are recorded separately in [Mac measurements](measurements.md). [Space switching](space-switching.md) expands the highest-priority interaction, and the [implementation plan](implementation-plan.md) sets the final sequence. No performance fixes have been applied.

Reviewed the installed SwiftUI expert skill and its latest API, observation, performance, list, layout, and image references. Cross-checked the applicable principles against Apple’s [Optimize SwiftUI performance with Instruments, WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/) and [Demystify SwiftUI performance, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10160/). Apple’s relevant guidance is to inspect actual dependency causes, reduce unnecessary view work, and measure before and after. No wholesale migration to a newer API or architecture is justified by this review.

## Assessment

The implementation has thoughtful performance engineering already: immutable domain snapshots, small named SwiftUI components, stable tab/Space identities, separate page state, background search preparation, careful favicon handling, and purpose-built drag registration. The strongest remaining opportunities are concentrated in the sidebar’s data dependencies and collection construction, followed by synchronous address completion. These fit incremental shared-core improvements; they do not require changing the working product’s interaction model.

## 1. Reuse the unfiled-row insertion projection once per section

**Priority: first / small change. Confidence: high source evidence; runtime benefit unmeasured.**

- [BrowserCurrentTabsDropSection.swift:90](../../../CrestShared/Features/Sidebar/Components/BrowserSidebarTabList/Components/BrowserCurrentTabsDropSection.swift#L90) loops the ordering projection; line 108 calls `renderRows([row])` separately for each tab block. Lines 118 and 139 read the computed `followingTabIDs`; lines 171–173 rebuild its full dictionary.
- [BrowserSavedTabsDropSection.swift:84](../../../CrestShared/Features/Sidebar/Components/BrowserSidebarTabList/Components/BrowserSavedTabsDropSection.swift#L84) does the equivalent iteration; line 105 calls `renderRows([item])`; lines 115/137 read the computed map, rebuilt at lines 176–180.
- [BrowserTabRowInsertionPolicy.swift:26](../../../CrestShared/Features/Sidebar/Components/BrowserSidebarDrag/Support/BrowserTabRowInsertionPolicy.swift#L26) constructs that map by allocating a mapped zip and a dictionary over the tab array.

For N unfiled tabs on a shell with row drop indicators, constructing all rows asks for an O(N) map N times. In Current, `tabs` also resolves through `BrowserTabSections.sidebarCurrentTabs`, which filters the current collection ([BrowserTabSections.swift:51](../../../CrestShared/Domain/BrowserSpace/Tabs/BrowserTabSections.swift#L51)). The source therefore contains avoidable quadratic collection work during section construction, before considering layout or page loading.

**Recommendation:** resolve the filtered tab run and following-ID map once before the outer `ForEach`, then pass the same map through `renderRows`. Hoisting only inside `renderRows` is insufficient because that function is called with a singleton array for each block. Consider one shared prepared section value that supplies order, following IDs, and motion IDs.

**Counterevidence:** this work is already skipped when `showsRowDropIndicators` is false. Folder rows already demonstrate the correct pattern: [BrowserFolderTabRows.swift:30](../../../CrestShared/Features/Sidebar/Components/BrowserFolderGroup/Components/BrowserFolderTabRows.swift#L30) materializes the map once and passes it into all row builders. Extend that existing practice instead of inventing a new framework.

**Validation:** use a synthetic Space with 50/200/500 unfiled current tabs and the same sizes for saved tabs. Count `followingTabIDs(in:)` invocations during initial presentation and one title update; expect one per section construction after the change, rather than roughly one per row. Compare main-thread section construction time and allocations in an optimized build. Exercise reorder across split groups and section boundaries because following IDs serve those interactions.

## 2. Narrow direct session observation in each sidebar row

**Priority: first / architectural follow-up. Confidence: high dependency evidence; fan-out and latency need a trace.**

- [BrowserStore.swift:7](../../../CrestShared/Application/BrowserStore/BrowserStore.swift#L7) stores the entire value-typed `BrowserSession` as one observable property. `selectedSpace`/`selectedTab` at lines 33–42 transitively read it.
- The sidebar root reads that property through `availableSpaces` ([BrowserSidebar.swift:97](../../../CrestShared/Features/Sidebar/BrowserSidebar.swift#L97), [BrowserSidebarAccessPolicy.swift:3](../../../CrestShared/Features/Sidebar/Support/BrowserSidebarAccessPolicy.swift#L3)).
- Each instantiated `BrowserSidebarTabRow` also reads it directly from its own body: [BrowserSidebarTabRow.swift:63](../../../CrestShared/Features/Sidebar/Components/BrowserSidebarTabRow/BrowserSidebarTabRow.swift#L63) evaluates `configuration.isCurrentAndUnlocked` for `.onChange`.
- That computed property calls the shared access policy and then `space.tabs.contains` ([BrowserSidebarTabRowConfiguration.swift:105](../../../CrestShared/Features/Sidebar/Components/BrowserSidebarTabRow/Models/BrowserSidebarTabRowConfiguration.swift#L105)). `selectedUnlockedSpace` reads `browser.session.selectedSpaceID` at [BrowserSidebarAccessPolicy.swift:25](../../../CrestShared/Features/Sidebar/Support/BrowserSidebarAccessPolicy.swift#L25) before resolving the live Space.

The row’s nominal input is one `BrowserTab`, but its access guard makes it a reader of the entire stored session. A real metadata update elsewhere in the session can invalidate these row bodies even when their displayed tab and availability have not changed. Reading a computed Boolean does not narrow Observation to the Boolean; equality of `.onChange` controls the callback, not the reads required to evaluate its argument. On the selected Space, the availability evaluation also repeats a linear tab membership scan for each row.

This is **not** evidence that every view in the application redraws. It establishes direct dependencies for the identified row and sidebar paths. SwiftUI can coalesce mutations and skip unchanged descendants, and views that never read `session` do not acquire this dependency merely by receiving a `BrowserStore` reference.

**Recommendation:** introduce a focused shared sidebar presentation projection with independently observable selection/access/structure and tab-display values. Keep the domain session as a value model if that is the desired core design. Feed rows only their displayed data and availability; maintain an indexed membership lookup where live membership is actually required. Retain the current runtime-assignment and lock checks when performing delayed actions. Simply adding `Equatable` to a row will not remove its direct observation reads.

**Counterevidence:** WebKit progress and loading properties live on individual page objects ([BrowserPage.swift:28](../../../CrestMac/Infrastructure/WebKit/BrowserPage.swift#L28), [MobileBrowserPage.swift:35](../../../CrestMobile/Infrastructure/WebKit/MobileBrowserPage.swift#L35)). `BrowserStore.updateTabFromPage` rejects unchanged URL/title/icon data before mutating session ([BrowserStore+TabLifecycle.swift:585](../../../CrestShared/Application/BrowserStore/BrowserStore+TabLifecycle.swift#L585)) and scopes/coalesces persistence at line 601. Do not report every progress tick as a session rewrite. The existing availability checks protect real stale-action cases and must survive any projection change.

**Validation:** on a Space with 200 tabs, observe three controlled transactions: selecting one tab; changing one visible title; changing a title in another Space. Inspect SwiftUI Instruments’ Cause & Effect Graph for `BrowserSidebarTabRow`, its content, and favicon descendants, recording body counts and total duration separately. Confirm unrelated displayed rows no longer have a session-wide cause after narrowing. Include lock/unlock, Space deletion, profile replacement, folder move, and a pending rename/popover when validating behavior.

## 3. Make tab-level laziness a deliberate large-library feature

**Priority: next / requires interaction design care. Confidence: high source evidence, medium impact confidence.**

- The macOS scroll wrapper has a `LazyVStack` at [SpaceSidebarTabListScroll.swift:24](../../../CrestMac/Features/Sidebar/BrowserSidebar/Components/SpaceSidebarContent/Components/SpaceSidebarTabListScroll.swift#L24).
- Its children are section views. Those sections each own an eager outer and inner `VStack`: `BrowserCurrentTabsDropSection.swift:32`/36 and `BrowserSavedTabsDropSection.swift:27`/29. Folder contents are also an eager stack ([BrowserFolderTabRows.swift:36](../../../CrestShared/Features/Sidebar/Components/BrowserFolderGroup/Components/BrowserFolderTabRows.swift#L36)).
- The mobile wrapper explicitly uses eager stacks at [MobileBrowserSpaceTabListScroll.swift:22](../../../CrestMobile/Features/Sidebar/MobileBrowserSidebar/Components/MobileBrowserSpaceTabListScroll.swift#L22) and explains at lines 3–9 that selected-row promotion depends on a resting source frame.

Desktop laziness is therefore at section granularity, not individual tab granularity. Once a large current or saved section is materialized, its rows, local state, favicon tasks, and geometry registrations scale with the section’s contents. The horizontal Space pager is lazy ([BrowserSpacePager.swift:41](../../../CrestShared/Features/Chrome/Components/BrowserSpacePager/BrowserSpacePager.swift#L41)), so this should not be described as eagerly instantiating every Space.

**Recommendation:** prepare an ordered row sequence including headers, tabs, split blocks, and folder depth, with stable semantic IDs, for a real row-level lazy container. Preserve selected/promoting/dragged rows deliberately; preposition and wait for the source measurement before an offscreen mobile promotion, or provide an intentional transition fallback. Prototype the shared projection and desktop virtualization first. A blind `VStack` → `LazyVStack` replacement on mobile risks undermining its existing animation contract.

**Counterevidence:** the eager mobile choice is documented and purposeful; collapsed folders avoid displaying all descendants; modest tab counts can be entirely adequate. Apple’s List/Table constant-row-count advice should not be misreported as a bug in every existing stack or conditional view.

**Validation:** measure first presentation, idle memory, row/task counts, scrolling, and Space swipes with 200/500 tabs and nested expanded folders. Require correct scrolling to an offscreen selected tab, promotion back to the sidebar, keyboard selection, drag autoscroll, and VoiceOver. Compare materialized rows to viewport demand, not just frame rate.

## 4. Finish moving address completion out of the keystroke path

**Priority: next / bounded optimization. Confidence: high source evidence, medium impact confidence.**

`BrowserCommandPaletteModel` is main-actor isolated. Its query setter calls `BrowserURLCompletion.proposal` synchronously ([BrowserCommandPaletteModel.swift:12](../../../CrestShared/Features/Chrome/Components/BrowserCommandPalette/Models/BrowserCommandPaletteModel.swift#L12)). The proposal rebuilds candidates from tabs and up to 1,500 history entries ([BrowserURLCompletion.swift:26](../../../CrestShared/Features/Chrome/Components/BrowserCommandPalette/Models/BrowserURLCompletion.swift#L26)), parses each URL with `URLComponents` (line 69), and sorts matches to take only the best result (line 48). The detached result preparation at `BrowserCommandPaletteModel.swift:234` is a different path and does not remove this work.

**Recommendation:** precompute normalized URL candidates once per palette/Space snapshot; use a running best candidate instead of sorting all matches. If measurements still show meaningful keystroke cost, prepare completion on the same cancellable worker path as local results, preserving query and IME-generation validation. Keep immediate Enter/Tab activation semantics explicit. Initial local result preparation is also synchronous at `BrowserCommandPaletteModel.swift:125`; assess first-open latency separately rather than assuming all search work is asynchronous.

**Counterevidence:** history is capped at 1,500 ([BrowserCommandPaletteResultTypes.swift:108](../../../CrestShared/Features/Chrome/Components/BrowserCommandPalette/Models/BrowserCommandPaletteResultTypes.swift#L108)), the query rejects many irrelevant inputs early, local result rebuilds are detached and cancellation-aware, and remote suggestions debounce 250 ms. This is not an unbounded full-history search finding.

**Validation:** with 1,500 history entries and 200 tabs, compare main-thread query-set duration and first-palette-open duration for a fixed typed URL sequence, repeated with an IME and rapid deletion. Assert identical ranking, suffix, and immediate Tab-then-Enter behavior while recording keystroke p95/p99 and completion availability latency.

## 5. Add a chrome-scale performance scenario alongside page-load soak

**Priority: enabling work for the changes above. Confidence: high.**

[BrowserPerformanceSoakFixture.swift:4](../../../CrestShared/Application/BrowserStore/Fixtures/BrowserPerformanceSoakFixture.swift#L4) caps the tab count at 24. The heavy scenario creates six Spaces (line 62) but only 96 history entries per Space (line 86). This is useful for repeated real page activity, but is not a representative stress case for the sidebar and completion costs above.

Add a separate deterministic, local, mostly unloaded library fixture with 200/500 tabs, nested folders, splits, and the 1,500-entry completion cap. Keep real loaded-page count controlled so browser-process memory does not obscure SwiftUI work. Use a host Mac or physical iPhone/iPad for the SwiftUI instrument; use Time Profiler and hitch data on Simulator. Record trace/source revision, workload, p95/p99 durations, body counts, and allocations. The source review provides candidates; the companion measurement report distinguishes the existing small-library trace from the larger fixture still needed.

## Existing strengths to preserve

- **Images:** `TabFaviconView.swift:24` keys task lifetime by a render identity; `BrowserFaviconTaskIdentityPolicy.swift:14` reuses a payload fingerprint already computed on the tab; `BrowserFaviconImageCache.swift:22` hashes on its actor and shares detached decode work at line 34; `BrowserFaviconImageDecoder.swift:24` downsamples with an explicit pixel cap. There is no basis to recommend replacing this with basic `AsyncImage` or claiming favicon decoding occurs in every body pass.
- **Utility search:** [BrowserUtilityListContent.swift:80](../../../CrestShared/Features/Utilities/BrowserUtilityListContent.swift#L80) debounces changed search text and prepares sections in a cancellable detached task. `BrowserUtilityListRequest.swift:3` excludes download progress from section-preparation identity. `BrowserUtilityListSectionList.swift:10` uses a native sectioned `List`.
- **Geometry:** `BrowserSidebarReorderState.swift:71` keeps row/zone/viewport registries outside observation. Registration freezes during a drag at lines 240–246, and the desktop pointer observer is deliberately isolated at `SpaceSidebarTabListScroll.swift:72`. Global per-row geometry callbacks are worth measuring with many rows, but the registry is not broadcasting every frame to the whole sidebar. Avoid an unsupported generic “GeometryReader is slow” recommendation.
- **Page continuity:** [BrowserPagePool.swift:1813](../../../CrestMac/Infrastructure/WebKit/BrowserPagePool.swift#L1813) intentionally retains pages until explicit unload or pressure. Pressure handling protects presented cards and checks actual runtime eligibility (`BrowserPagePool.swift:2293`). Automatic aggressive eviction would trade away the snappiness the user values; evaluate app/WebContent memory together before changing this policy. Existing lifecycle signposts in the page, pool, and host provide useful correlation.
- **Domain work:** the store’s session setter also reconciles selection history (`BrowserStore.swift:8`, `BrowserTabSelectionHistory.swift:8`) across Spaces for every actual mutation. This is a secondary profiling target within the observation/projection follow-up, not a separately demonstrated bottleneck. Structural and selection revisions could eventually avoid reconciling history for title-only updates.

Verification of this audit: source anchors inspected at the stated revision; `git status --short` was clean immediately before writing this `/tmp` report. No runtime performance result is asserted.
