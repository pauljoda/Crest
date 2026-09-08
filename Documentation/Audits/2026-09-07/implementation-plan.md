# Implementation plan

Baseline: `457ac1d2`, September 7, 2026. This plan turns the audit into independently reviewable changes. Space switching is the first product milestone: a horizontal gesture immediately moves the actual neighboring sidebar with the fingers, then settles to at most one adjacent Space using release velocity. This incorporates the subsequent physical feedback rejecting threshold-triggered fixed animations. Remove the free-scrolling horizontal strip; keep vertical tab scrolling. Extension responsiveness and ownership cleanup follow. This plan describes the audited baseline; delivered changes and their remaining acceptance work are tracked in [implementation progress](implementation-progress.md). Use [measurements.md](measurements.md) for original observations and limits, and [validation.md](validation.md) for original checks and known failures.

The intended result is smoother native interaction with fewer repeated computations and clearer shared owners. File count, line count, and shared-source percentage are not acceptance metrics. Keep native page hosts and input adapters where their behavior differs; put common decisions and workflows in the relevant shared Domain, Application, or presentation feature.

## Working rules

Implementation currently proceeds as reviewable commits directly on local main, as requested. The numbered packages describe cohesive review boundaries; references to PRs below describe those boundaries rather than a requirement to create a branch or worktree. Record its baseline, concrete changed behavior/work, relevant retained coverage, and before/after evidence. Avoid combining mechanical renames with a performance experiment or lifecycle extraction.

Follow [test-retention.md](test-retention.md) and the local repository `AGENTS.md`. Reuse existing durable browsing, persistence, authorization, extension-compatibility, and platform-adapter coverage. Temporary probes, counters, synthetic fixtures, and experiments can establish cause; remove them before handoff unless they become a deliberately supported performance scenario. Keep a new regression only when it protects an important contract not already covered. Consolidate overlapping cases and fixtures; do not add a permanent test per helper, cache field, filename, or source arrangement.

When removing a test, identify its contract and the stronger retained coverage, or why the contract is obsolete. Distinct AppKit/UIKit integration behavior still deserves distinct coverage. A failing expectation is investigated before removal. Each app-code commit follows the repository's version and release-note requirements; routine development increments the patch on the current release line (main was `0.5.80` when implementation began).

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

## 4. Move actual neighboring pages with the gesture

**Dependency:** 2–3. Use a small Mac native event adapter to classify the horizontal axis while preserving vertical scrolling and gestures outside the sidebar. Precise phased trackpad events move the retained native views by their scrolling distance in points. A slow drag follows each sample; a fast release supplies recent velocity to settling. One stream has at most one adjacent destination, and reversing can return to its origin. Keep bounded burst handling for ordinary wheels and phase-less events; momentum must not trigger another Space change.

A per-window native viewport owns transient position and completion generation. Fresh gestures interrupt settling at the actual presentation position. Native view frames, clipping, hit testing and accessibility must remain coherent; backing-layer transforms must not contradict their owning views' geometry. Keep the arriving view mounted after completion. Physical paging commits browsing selection after visual settling; adjacent external selections animate the already-authorized change. Direct distant choices present their target without compressing unrelated pages into a false neighboring strip. Assignment, privacy, drag-lock, layout direction, Reduce Motion and window lifecycle changes invalidate or finish motion coherently.

Navigation, URL editing and extension controls stay fixed above the moving Space header, folders and tabs. The icon strip follows actual fractional page position in a small native presentation leaf. Global browsing state and all row bodies must not subscribe to progress samples. Retained content refresh and page activation must not delay the next input; any deferral must still deliver current content, callbacks, privacy and selected role when motion ends or cancels.

**Acceptance:** immediate finger-following movement, velocity-aware release, continuous interruption and one adjacent commit per gesture; no text overlap, backing flash, view replacement or end snap. Verify slow drag, flick, reversal, resize, separate rapid gestures, vertical scrolling, wheel bursts, privacy changes and Reduce Motion with real tool captures and physical feedback. Command recordings are useful comparisons but do not certify trackpad feel. Retain compact native geometry/lifecycle and input-policy coverage; remove diagnostic-only counters and obsolete snapshot/snap assertions. Reuse host/focus/split/unloaded-entry coverage.

## 5. Prepare bounded neighboring chrome

**Dependency:** 2–4. Prepare immutable current/previous/next sidebar data after settlement; cancel obsolete work. Cache structural row order, folder depth, following IDs, access, and branding inputs by Space/profile and relevant revision. Retain inexpensive data more broadly than live view trees.

Prototype desktop row-level virtualization as a separate PR if the scale trace still warrants it. Preserve selected/promoting/dragged source materialization; mobile's resting-frame contract requires an intentional offscreen-promotion path, not a blanket stack replacement.

**Acceptance:** the switch consumes prepared values; retained views/tasks track the bounded working set and viewport rather than three eager 500-row sections. Check drag autoscroll, keyboard/offscreen selection, VoiceOver, and mobile promotion. Previously visited WebKit pages already remain resident. Automatic loading of remembered unloaded tabs is a separate product-policy change and is excluded here. Experiment with a bounded resident host surface only if attachment remains a measured bottleneck.

## 6. Coordinate the branding transition

**Dependency:** 4–5 and passing lifecycle gates. Use stable branding inputs for a coherent color transition, with the native pager providing any required presentation progress. Identical branding must remain visually unchanged across Space IDs; do not replace and fade the same background on each selection. Keep window material, widgets, and WebKit host layout stable; do not duplicate or resize live pages to animate them. Profile texture redraw before introducing texture caching.

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
