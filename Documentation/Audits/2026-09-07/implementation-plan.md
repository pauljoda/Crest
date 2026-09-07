# Implementation plan

Baseline: `457ac1d2`, September 7, 2026. This plan turns the audit into independently reviewable changes. Space switching is the first product milestone: one horizontal gesture requests one adjacent Space and starts a fixed transition. Remove the free-scrolling horizontal strip; keep vertical tab scrolling. Extension responsiveness and ownership cleanup follow. No optimization below is implemented or claimed to meet its targets. Use [measurements.md](measurements.md) for observed results and limits, and [validation.md](validation.md) for executed checks and known failures.

The intended result is smoother native interaction with fewer repeated computations and clearer shared owners. File count, line count, and shared-source percentage are not acceptance metrics. Keep native page hosts and input adapters where their behavior differs; put common decisions and workflows in the relevant shared Domain, Application, or presentation feature.

## Working rules

Each numbered package should produce one small PR, or several explicitly separated PRs where stated. Record its baseline, concrete changed behavior/work, relevant retained coverage, and before/after evidence. Avoid combining mechanical renames with a performance experiment or lifecycle extraction.

Follow [test-retention.md](test-retention.md) and the local repository `AGENTS.md`. Reuse existing durable browsing, persistence, authorization, extension-compatibility, and platform-adapter coverage. Temporary probes, counters, synthetic fixtures, and experiments can establish cause; remove them before handoff unless they become a deliberately supported performance scenario. Keep a new regression only when it protects an important contract not already covered. Consolidate overlapping cases and fixtures; do not add a permanent test per helper, cache field, filename, or source arrangement.

When removing a test, identify its contract and the stronger retained coverage, or why the contract is obsolete. Distinct AppKit/UIKit integration behavior still deserves distinct coverage. A failing expectation is investigated before removal. Each app-code commit follows the repository's version and release-note requirements; routine development stays on the current `0.4.x` line.

## 1. Establish comparable interaction measurements

**Dependency:** none. Use the isolated optimized-build setup in [measurements.md](measurements.md); retain package identity, device/display rate, source revision, and workload with the result. Repair misleading timing before using it as an acceptance gate.

Measure gesture recognition and accepted Space intent through the next presented frame, separating publication, projection, page selection, attachment, SwiftUI update, and render/hitch cost. Include physical trackpad/wheel streams; synthetic input alone cannot certify segmentation. Explicitly load each selected group before warm switching; unloaded entry is a separate Start Page scenario. Add a temporary mostly unloaded 200/500-tab fixture with nested folders and controlled resident-page count.

Pair Space captures with and without frequent accessibility-tree reads. Computer Use observation can itself trigger focus/update work; inspect selected-picker reveal/focus separately. Tool command-plus-state-capture elapsed time is not click latency, and synthetic scrolling is not a physical-gesture reproduction.

For extensions, time the original first action through meaningful popup content. Separate cold, warm, expired-cache, idle, and demonstrated recovery cases. Remove prewarming and the four-second pre-timing sleep from that measurement path. MV2 background pages and MV3 workers are different fixtures. Existing eventual-readiness tests remain useful, but do not establish latency.

**Acceptance:** reproducible p50/p95/p99 durations, update/projection counts, hitch counts, and app plus WebContent memory for comparable workloads. Record navigation/paint/theme completion separately. Capture IDs and stage timing without collecting credential-bearing URLs, storage, or message bodies.

## 2. Prepare sidebar rows once per relevant change

**Dependency:** 1. Follow the concrete [SwiftUI findings](swiftui-performance.md).

First PR: compute current/saved tab runs and following-ID maps once before each section's outer iteration. Pass the prepared value through row construction, matching the existing folder pattern.

Second PR: give sidebar rows focused display/access inputs and indexed membership. Remove their read-only dependency on the whole observable session while preserving live authorization and Space/profile-assignment checks when actions execute. Key preparation by structure, displayed metadata, and access inputs; progress elsewhere must not rebuild unrelated row data.

**Acceptance:** one following-ID map per section construction, rather than one per row; unrelated title updates do not cause row-wide session observation work. Compare body counts, construction time, and allocations at 50/200/500 tabs. Reuse reorder, split, folder, lock, and stale-action coverage; temporary invocation counters do not need permanent helper tests.

## 3. Make selection a narrow transaction

**Dependency:** 1; coordinate with 2 and extension metadata work in 9. Follow the [actual selection call chain](space-switching.md).

Separate selection change from structural/content revision. Keep durable and per-window selection ownership explicit; other windows retain their own selection without rebuilding their sessions for a local switch. Route the selection delta to presented cards and required extension active-state events once. Reserve full assignment maps, archive pruning, group repair, icon/content-blocking projections, and credential reconciliation for inputs that affect them.

**Acceptance:** one winning presentation transaction and one necessary extension selection update per committed switch, including all required split-card events; zero unrelated structural/icon/permission rebuilds. Unchanged resident groups create zero new pages and start zero initial navigations. Existing independent-window, sync-coalescing, runtime-identity, and unloaded-entry contracts pass. Do not replace required extension events with a stale snapshot to reach a count target.

## 4. Replace free scrolling with one-step intent and fixed motion

**Dependency:** 2–3. First PR: replace the horizontal Space `ScrollView`/snap loop with a small shared intent policy and thin Mac `NSEvent` adapter. Normalize deltas/units, phase, momentum, and timestamps. Lock deliberate horizontal intent; preserve vertical tab scrolling. Emit one step at threshold, latch through gesture/momentum, and cancel an abandoned pre-acceptance reversal. Phase-less precise streams and ordinary-wheel bursts use bounded accumulation plus a last-event idle boundary; never rearm by time since the last step or debounce each delta into another action. Calibrate thresholds physically rather than copying widget constants.

Second PR: one per-window owner coordinates requested/presented assignment, fixed animation, and generation. Keyboard, picker/slider, auxiliary buttons, touch, and accessibility Previous/Next/adjustable actions enter the same request path. Animation progress is independent of deltas. Keep one active transition and at most one coalesced pending adjacent step for distinct rapid gestures; direct targets supersede pending work. Preserve access and existing end behavior (gesture/accessibility clamp, keyboard adjacency wraps) through explicit request policy, plus immediate coherent resident-page handoff. Relock/delete/profile changes invalidate stale completion; Reduce Motion settles immediately without releasing the gesture latch.

**Acceptance:** one gesture/burst causes at most one adjacent commit, momentum none; vertical scrolling stays native. Separate gestures remain responsive without an unbounded queue. Retain one table-driven intent contract, focused adapter pass-through/phase coverage, and the compact generation/cancellation lifecycle contract where needed. Reuse real host/focus/split/unloaded-entry coverage and replace obsolete snap/flag assertions with retained behavior. Follow the [physical input matrix](space-switching.md).

## 5. Prepare bounded neighboring chrome

**Dependency:** 2–4. Prepare immutable current/previous/next sidebar data after settlement; cancel obsolete work. Cache structural row order, folder depth, following IDs, access, and branding inputs by Space/profile and relevant revision. Retain inexpensive data more broadly than live view trees.

Prototype desktop row-level virtualization as a separate PR if the scale trace still warrants it. Preserve selected/promoting/dragged source materialization; mobile's resting-frame contract requires an intentional offscreen-promotion path, not a blanket stack replacement.

**Acceptance:** the switch consumes prepared values; retained views/tasks track the bounded working set and viewport rather than three eager 500-row sections. Check drag autoscroll, keyboard/offscreen selection, VoiceOver, and mobile promotion. Previously visited WebKit pages already remain resident. Automatic loading of remembered unloaded tabs is a separate product-policy change and is excluded here. Experiment with a bounded resident host surface only if attachment remains a measured bottleneck.

## 6. Coordinate the branding transition

**Dependency:** 4–5 and passing lifecycle gates. Use stable outgoing/incoming branding inputs and the owner’s fixed animation progress for a clipped color reveal or crossfade; remaining scroll deltas never drive the wipe. Keep window material, widgets, and WebKit host layout stable; do not duplicate or resize live pages to animate them. Profile texture redraw before introducing texture caching.

**Acceptance:** foreground contrast remains readable throughout; Reduce Motion/Transparency retain coherent alternatives. Proposed budgets are next-frame acknowledgment, Crest synchronous input work ≤2 ms, and warm main-thread update work approximately <4 ms at 120 Hz or <8 ms at 60 Hz. These leave part of the 8.33/16.67 ms frame for rendering; they are proposed targets, not results or platform guarantees. Report p95/p99, hitches, and memory for a fixed warmed sequence. The milestone needs smooth measured handoffs, not merely a shorter animation.

## 7. Unify extension readiness and recovery

**Dependency:** 1; can proceed independently after the Space milestone's shared contracts settle. Follow [extensions.md](extensions.md).

First PR: one per-context readiness owner lets startup, hover, and action callers join preparation using context generation. Preserve recovery authority: hover may prepare, while an actual action authorizes eligible persistent-context recovery. Distinguish bridge transport health from an extension's asynchronous initialization. Keep delayed-listener behavior protected while replacing measured redundant grace periods.

Second PR, only if reproduction requires it: refine on-demand recovery around the observed failure. Do not infer worker eviction from elapsed idle or apply a worker fix to the pinned MV2 Firefox package.

**Acceptance:** at most one concurrent preparation/recovery per context generation; no stale completion, duplicate action, lost first message, or hover-triggered reload. Report original click-to-content and stage durations for each lifecycle state. Preserve storage, ports, native events, action identity, pending promises, and typed page state. Avoid vendor patches, fabricated success, unconditional reloads, or permanent worker keepalive. Retain one focused concurrent-action/replacement contract where existing coverage is insufficient.

## 8. Make unchanged extension preparation cheap

**Dependency:** 1; independent of 7's ownership after interfaces are agreed. Move archive/file/script work to an explicitly isolated async service; WebKit context mutation remains on the main actor. Then add an early cache keyed by verified package content, preparation/runtime version, manifest/permission inputs, runtime identity, and injected capabilities. Keep mutable unpacked-source invalidation explicit.

**Acceptance:** an unchanged validated cache hit skips full copy/extract/rewrite/hash preparation. Concurrent identical requests share one preparation; publication is atomic with stable resource URLs and compatible retained resources. Compare main-thread time, bytes read/written, and peak temporary disk for 1/5/10 installations. Reuse prepared-package/restore coverage and consolidate invalidation cases into the owning cache contract; do not test directory topology.

## 9. Index extension metadata and separate runtime assembly

**Dependency:** 3 and the measurement contract from 1. Use direct authorized per-tab reads or an indexed projection updated once per relevant transaction. Include live loading/reader state, transient announcements, auxiliary windows, and group membership in invalidation. Returning `lastState` blindly is insufficient.

**Acceptance:** enumeration work grows with relevant returned tabs rather than multiplying full-session projections by property reads. Compare projection/activity-call counts at 50/200/1,000 tabs; preserve current identity and event order.

In a separate PR, split package publication, manifest/context normalization, and deterministic runtime assembly into cohesive owners with explicit transport/error/context inputs. Preserve native namespace/event identity, callback/Promise and `lastError` semantics, execution-world isolation, permissions, and Space boundaries. Keep existing native WebKit compatibility fixtures; do not replace them all with JavaScript mocks or enable mobile extensions implicitly. Change emitted bundle composition only when measured startup work justifies it.

## 10. Simplify names and locations mechanically

**Dependency:** stable touched interfaces; avoid overlapping moves with 2–9. Apply the reviewed [organization map](organization.md) one feature at a time.

Path-only PRs consolidate `Extensions`, `Downloads`, `Favicons`, `Authentication`, and other actual capabilities, shorten redundant `Browser` filenames, and update project generation/guard references without renaming declarations. Separate symbol PRs use precise names such as `SessionStore`, `ExtensionControllerPool`, and `AppCommands`; retain meaningful `DefaultBrowser` and qualify `SwiftUI.Tab` where needed.

**Acceptance:** both targets build with correct membership; persisted keys, Codable fields, archive framing, CloudKit identifiers, Keychain namespaces, selectors, JavaScript APIs/messages, and localization identifiers remain compatible. Review literal changes explicitly. No new source-shape tests are required for mechanical moves.

## 11. Consolidate behavior at cohesive ownership boundaries

**Dependency:** settled relevant performance work and mechanical naming slices. Deliver separate PRs for shared tab-state lifecycle, page reconciliation, content-blocking coordination, and common command intent. Keep platform capture/release, suspended desktop pages, native focus/window behavior, and iPad aliases in adapters.

Move drag/geometry state to shared Sidebar presentation; neutral popup and data-portability contracts move inward to their relevant Application/Domain feature. Co-locate proven private favicon/codec helpers. Separately group download-session lifecycle and approval responsibilities, and split widget deck/playback/update components as described in [organization.md](organization.md). Avoid a universal page superclass, a generic Shared bucket, or one file per helper.

**Acceptance:** each common behavior has one implementation and one owning behavioral suite, with distinct platform integration retained. Archive restoration, private-mode suppression, multiwindow drag independence, command ordering, download cleanup, and widget continuity remain covered. Consolidate duplicate policy/platform assertions as ownership moves; document retained protection.

## 12. Finish bounded cleanup and close the milestone

After primary latency work, normalize address-completion candidates once per snapshot and select the best match without sorting everything; use cancellable off-main work only if keystroke measurements warrant it. Preserve IME and immediate Tab/Enter behavior. Replace remaining platform-selected UI policies with capability/action inputs when those components change.

Resolve the recorded stale mobile palette expectation and maintenance-check failures according to their real contracts. Run affected retained suites, both app builds for shared changes, and supported architecture, source, formatting, and version checks. Compare optimized workloads to the baseline. Handoff includes results, remaining gaps, and removed temporary/duplicate tests with their retained coverage; green checks alone do not establish smoother interaction.
