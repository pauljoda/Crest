# Crest quality, architecture, and performance audit

Audited commit: `457ac1d2c9bc78011e595664053f24df50ae2249`, September 7, 2026. Worktree branch: `codex/code-quality-audit-2026-09-07`. This report stays pinned to that revision; later changes on `main` require revalidation.

**Crest has a strong shared foundation. The next pass should make Space switching consistently smooth, shorten extension readiness and recovery, and simplify ownership as those paths change.** The architecture supports the Arc-replacement ambition. The largest remaining costs come from broad work triggered by narrow interactions, repeated platform orchestration, and several owners with unrelated responsibilities.

The requested naming cleanup fits this assessment. `Browser` is redundant across most internal names: 22 of the 30 immediate Shared Infrastructure directories carry it. Consolidate extension infrastructure under `Extensions`, give other capabilities similarly simple homes, and keep small private helpers beside their owner. Useful feature names, framework distinctions, and durable storage/API identifiers still matter.

This audit records the original baseline and implementation direction. Subsequent changes on main, validation, and remaining performance acceptance work are recorded separately in [implementation progress](implementation-progress.md). Source-backed costs, observed baseline results, and proposed acceptance targets are distinguished throughout.

## Start here

| Document | Purpose |
| --- | --- |
| [Implementation progress](implementation-progress.md) | Changes delivered on main, current validation and remaining acceptance work |
| [Implementation plan](implementation-plan.md) | Ordered work packages, dependencies, behavioral safeguards, and acceptance gates |
| [Space switching](space-switching.md) | Actual selection/reconciliation chain; shared transition owner; bounded preparation; color wipe |
| [Mac measurements](measurements.md) | Isolated optimized-build trace, exact extension fixture, results and measurement limits |
| [Extension audit](extensions.md) | API mapping, package preparation, popup readiness, idle recovery, compatibility matrix |
| [Organization map](organization.md) | Concrete folder/file moves, cohesive owners, collision and migration checks |
| [Shared core and capabilities](core-and-capabilities.md) | Repeated lifecycle/command behavior and remaining inward dependency leaks |
| [SwiftUI review](swiftui-performance.md) | Observation, row preparation/laziness, completion, and existing optimizations |
| [Test retention](test-retention.md) | Essential contracts, redundant checks, and removal/consolidation directions |
| [Validation evidence](validation.md) | Build/check/test commands, failures, warnings, and scope |

## What changes the priorities

**Space selection is the first product milestone.** It changes durable session state, publishes to the shared window family, selects resident pages, recomputes broad runtime projections, and can trigger another global reconciliation. Sidebar rows also depend on broad session state and repeatedly derive collection values. These are concrete reasons to establish a selection-only path and narrower prepared presentation data before paying for additional live pages.

Crest already retains visited pages and has a lazy horizontal Space pager. Entering a Space whose selected page is unloaded intentionally presents Start Page; blindly enabling automatic loading or delaying page selection would change that contract. Prepare current/adjacent chrome and reuse resident content first. Treat a horizontal gesture as one adjacent-Space request and drive a fixed transition; replace free horizontal scrolling and snapping where needed. Coordinate requested selection, actual presentation, and a restrained color wipe through one cancellable transition owner. Momentum must not trigger additional steps within the same gesture. Animation must remain independent of network completion and must pass hitch measurement.

**Extension responsiveness needs a lifecycle change, not just a smaller spinner.** Startup and popup preparation have separate coordination. Popup opening can pass through a fixed 750 ms warmup, health checks, persistent-context recovery, and presentation fallback; a three-second stage deadline is not a total action deadline. A transport health response proves the bridge responds, not that an extension has finished its own storage/configuration startup. Unchanged package restore also performs synchronous preparation before discovering a reusable output.

The installed Dark Reader package inspected for the isolated fixture is Firefox 4.9.129, Manifest V2 with a background page. Its stalls must not automatically be attributed to Manifest V3 worker eviction. The exact package passed persistent restoration followed by 45 seconds idle, but the existing test waits four seconds before starting its readiness timer. That proves eventual readiness in the tested scenario; it does not prove fast first-click recovery. Navigation stalls and popup delays need separate correlated measurements before assigning one cause.

**Organization should reduce navigation and change overhead.** Shared extension infrastructure currently spans five principal subtrees plus loose files: 102 files and 12,919 raw lines. Consolidate by installation/runtime/compatibility/source lifecycle. Move reused neutral contracts inward, keep reused UI contracts with shared presentation, and leave native adapters in their platform root. Decompose the package preparer, page runtime, downloads, and widget host at real ownership boundaries. Do not replace large owners with dozens of extension files that still share all their state.

**Keep the permanent test suite small in purpose.** Retain key browsing, persistence, authorization, compatibility, and performance contracts. Temporary reproductions and diagnostic probes should be removed once the work is complete; duplicate implementation-shape assertions should be consolidated or retired. A test’s origin in a bug fix does not decide its value. The local repository `AGENTS.md` now records this retention policy. The first cleanup removed 11 low-value or duplicate methods and seven redundant extension assertions (209 lines). **221 retained Swift tests and 11 Python tests passed** afterward. The [test review](test-retention.md) maps removals to remaining protection; these runs overlap earlier suites and should not be summed as unique coverage.

## Overall assessment

| Area | Assessment | Implementation direction |
| --- | --- | --- |
| Shared core | Durable browsing behavior is substantially shared | Share page lifecycle and command execution; remove presentation-owned dependencies from inward layers |
| Input capabilities | Touch/hover policies and shortcut metadata are established | Route common intent through one behavior owner; keep native input adapters |
| SwiftUI | Modern Observation and several deliberate caching/lifetime optimizations | Narrow dependencies; prepare indexed row data once; profile before deeper virtualization |
| Extension mapping | Explicit native/emulated/unsupported treatment and shared Space/tab identity | Preserve the matrix and tested semantics while improving lifecycle and metadata cost |
| File organization | Meaningful domains exist, but names and ownership are scattered | Drop redundant prefixes; consolidate private helpers and related infrastructure |
| Validation | Extensive tests and guardrails, incomplete CI enforcement | Repair stale checks; require behavior tests and reproducible performance evidence |

No architectural rewrite, universal page superclass, or immediate package extraction is warranted. Mobile extension support is deliberately disabled; shared source is not evidence that it ships there. Common command execution is a more useful next step than adding a keyboard capability flag that carries no independent policy.

## Inventory and validation

The production tree contains 2,287 Swift files and 217,566 raw lines. Shared has 1,446 files and 61.7% of raw lines, or 56.1% after excluding the generated emoji catalog. Those are inventory measures, not percentages of shared behavior. Scans found 78 `@Observable` occurrences and no `ObservableObject`, `@Published`, or `AnyView`. See [metrics](metrics.json).

The initial audit passed architecture, vertical structure, identity, cache/public-source hygiene, licenses, and release catalog checks. It passed 117 macOS tests. The final extension pass added six passing tests, including the pinned Dark Reader package. Of 52 iOS tests, 51 passed; one stale cross-Space palette expectation caused five assertions. The Python suite ran 145 tests with one failure and one class-setup error. Full Swift formatting lint reported 252 diagnostics in 38 files; each platform build emitted three production actor-isolation warning occurrences. These are documented maintenance tasks, not evidence that the app needs behavior changes to satisfy stale expectations.

The Mac performance pass uses the existing isolated Release fixture and Xcode Instruments. A usable Time Profiler capture recorded a **267.45 ms main-thread microhang during warm Space switching**; SwiftUI and Animation Hitches captures did not finalize within practical resource limits. This is observed diagnostic evidence, not a measured fix or a complete frame-budget baseline. A subsequent Computer Use pass verified each requested destination and exposed substantial accessibility/focus work; its inspection overhead is reported separately. Read [measurements](measurements.md) for the measured scope and remaining gaps; a Debug test duration cannot establish shipping latency, and one package pass cannot renew the full extension certification matrix.

SwiftUI guidance was reviewed using the locally available SwiftUI Expert skill and Apple's primary guidance on dependency-driven updates, expensive bodies, stable identity, and Instruments attribution. [Apple WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/), [Apple WWDC23](https://developer.apple.com/videos/play/wwdc2023/10160/), [SwiftUI Expert source](https://github.com/AvdLee/SwiftUI-Agent-Skill).
