# Performance pass closeout — September 8, 2026

The 0.5.87 work on local `main` preserves the accepted Space motion and removes additional measured work from address editing and extension startup/action paths. This is the closeout of the bounded performance pass, not a claim that every structural package in the original audit has shipped. The [implementation history](implementation-progress.md) records the earlier physical feedback, rejected experiments, mobile fixes, and Arc comparison. The original audit remains pinned to its baseline.

## Retained improvements

| Area | Delivered behavior | Evidence |
| --- | --- | --- |
| Space presentation | Actual retained native sidebar views; bounded neighboring layouts; continuous interruption; fixed navigation chrome; background, foreground, picker, and optional page-card motion share presentation progress | Earlier physical acceptance, native geometry/gesture contracts, Arc frame comparisons, and mobile device checks in the implementation history |
| Vertical scrolling | Accept the proposed native pager viewport size instead of fitting retained page subtrees during scrolling | Matched main-thread samples fell from 5,306 to 2,903 ms over 6.5 seconds; native fitting samples fell to zero. A separate paired capture reduced recorded hitch time by about 12%, not to zero |
| Local address completion | Parse candidates once per immutable palette snapshot, normalize each query once, and retain the best match without sorting | At 1,000 tabs plus 1,500 history entries, optimized query p95 fell from 11.37 to 1.21 ms; 26,350 proposals matched the old algorithm |
| Stored extension preparation | Run archive, filesystem, and script preparation off the UI executor; reuse unchanged prepared output before extraction or rewriting | Five Dark Reader preparations previously blocked the main actor for up to 126.40 ms; the asynchronous/cache run's maximum heartbeat gap was 3.70 ms, with warm preparation taking 0.93–1.41 ms |
| Extension readiness | Startup, hover, and action join one preparation generation. A successfully settled background endpoint can be reused after idle, with a fresh health challenge on every action | Original first-click content after restoration and 45 seconds idle: 1,482 ms baseline; 911 ms candidate and 708 ms final repeat. Cold first-click content remains around 1.45 seconds |
| Extension tab identity/selection | Enumerate authorized tab IDs and selected identity without projecting every tab's live page/reader state | The 1,000-tab identity/selection case fell from 2,012 page reads to zero; the retained contract also covers 50 and 200 tabs, live metadata, and detached state |

These figures measure different things and must not be added together. Optimized algorithm timings, Debug WebKit integration timings, main-actor scheduling gaps, CPU samples, and presented-frame hitches are labeled separately below.

## Address completion

`BrowserURLCompletion.Candidates` belongs to the existing completion domain and is cached lazily by `BrowserCommandPaletteModel`, whose Space snapshot is immutable. Its first eligible use still performs preparation; at the largest measured fixture this took 2.28 ms. Subsequent keystrokes reuse normalized candidates. Completion remains synchronous so immediate Tab/Enter handling and the existing IME/live-source protections retain their behavior.

The disposable harness compiled the actual baseline and candidate algorithms with `swiftc -O`, supplying small model stubs for their data dependencies. Each scale uses 1,500 history entries and ten queries, with 30 recorded repetitions after warmup. This measures algorithm cost, not application keystroke-to-frame latency.

| Tabs | Baseline p50 / p95 / p99, ms | Candidate p50 / p95 / p99, ms |
| ---: | ---: | ---: |
| 50 | 3.65 / 4.41 / 4.67 | 0.51 / 0.65 / 0.70 |
| 200 | 4.59 / 5.58 / 5.81 | 0.58 / 0.75 / 0.81 |
| 500 | 5.81 / 7.23 / 7.38 | 0.71 / 0.92 / 1.15 |
| 1,000 | 9.51 / 11.37 / 11.55 | 0.95 / 1.21 / 1.26 |

The differential oracle checked 26,350 cases, including exact-match suppression, ordering/ranking, case-sensitive paths, schemes, ports, IPv6, credentials, queries/fragments, and Unicode insertion ranges. Existing native editing and completion suites remain the permanent protection; the benchmark and oracle stay outside the repository.

Repeating the oracle against the final source again matched all 26,350 cases. Its 1,000-tab p50/p95/p99 were 0.93/1.19/1.26 ms, with 2.24 ms preparation, consistent with the comparison above.

## Larger sidebar workloads

The existing isolated heavy fixture now supports up to 500 tabs per Space without raising the normal page-load fixture's 24-tab limit. Time Profiler and full-window captures exercised 50, 200, and 500 tabs in each of nine Spaces (450, 1,800, and 4,500 tabs total), with eight expanded folders per Space and mostly unloaded pages. The visible first page was loaded; no media playback was requested and the served fixture's mutation counter remained zero. The selected Daylight Space uses the same chevron background across runs; other template patterns are shuffled on launch.

Each optimized run used the same 1728 × 995-point window and six alternating 1.6-second native vertical bursts at 120 events/second, with delivered deltas ±5, ±7, and ±3 points. There were no builds or tests running during these captures and no accessibility-tree polling. As in the earlier vertical comparison, the first burst is excluded for profiler attachment. The table uses five 1.3-second intervals, beginning 150 ms into bursts two through six, aligned through the native input clock and trace start time.

| Tabs per Space | Sampled main-thread time over 6.5 s | Native fitting samples | App RSS before / after capture |
| ---: | ---: | ---: | ---: |
| 50 | 3,669 ms | 0 ms | 186 / 235 MiB |
| 200 | 4,618 ms | 0 ms | 338 / 286 MiB |
| 500 | 6,085 ms | 0 ms | 494 / 526 MiB |

This is a scale characterization of the final build, not a matched before/after comparison at these larger sizes. The captures still show uneven motion; they do not establish smooth 120 Hz scrolling. At 500 tabs per Space, sampled main-thread work occupies about 94% of the selected intervals. SwiftUI graph/layout and native hit testing remain prominent; full-trace `SpacePagerViewport.hitTest` inclusive samples rise from 515 to 1,492 ms across the 50-to-500 range. Those inclusive totals cover the whole trace, not only the 6.5-second intervals.

RSS is a pair of app-process observations, not peak memory, a leak slope, or combined app-plus-WebContent usage. In particular, the 200-tab decline illustrates allocator/reclamation variability. These measurements support a separate large-list rendering/observation effort; they do not justify retaining every Space's full layout or changing the mobile offscreen-promotion contract during closeout. The earlier accepted motion settings remain unchanged.

## Extension preparation and readiness

The shared stored-resource interface is asynchronous. Its Mac adapter passes immutable inputs to filesystem preparation and returns the prepared resource to the main actor before WebKit mutation. Publication remains serialized and atomic, with stable resource URLs, prior generated worker resources, and the existing clipboard capability preserved. Cancellation is checked before preparation and before returning a result; synchronous archive work already in progress is not forcibly interrupted.

The early receipt includes source content, requested permissions, console-capture configuration, and preparation/build identity. Its location also incorporates the source path and full runtime/Space identity. Mutable directory inputs are hashed too. An unchanged hit still reads/hashes source bytes and reads the prepared manifest; it skips expansion, copying, script rewriting, and prepared-tree hashing. This is a preparation cache, not a claim of zero I/O or a replacement for package verification. Developer rebuilds invalidate it even when the marketing version has not changed.

Delegate-free Foundation file operations run in the worker; AppKit/WebKit ownership remains on the main actor. See Apple's [filesystem performance guidance](https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system) and [FileManager threading considerations](https://developer.apple.com/documentation/foundation/filemanager). The two immutable transfer types document their checked ownership assumptions where the SDK's FileManager type lacks Sendable conformance.

The measured fixture is the existing Firefox Dark Reader 4.9.129 package, Manifest V2, `addon@darkreader.org`, copied into an isolated test fixture. Archive SHA-256: `f4f047fe08e420b6d29617738ea00a7b784892b2262b7e6f38dd09b8ee958a44` (856,583 bytes). Each live run uses fresh Space/profile identities and its own extension data.

- Baseline five synchronous preparations: 88.88, 93.19, 92.90, 93.37, and 124.45 ms. Maximum main-actor heartbeat gap: 126.40 ms.
- Candidate first asynchronous preparation: 62.55 ms wall time; four unchanged hits: 1.41, 1.04, 0.93, and 0.97 ms. Maximum main-actor heartbeat gap: 3.70 ms. These are Debug integration measurements with a 2 ms heartbeat, not Instruments frame measurements.
- The existing restore contract now checks concurrent reuse, permission invalidation, changed archive bytes, stable resource identity, and native loadability. Existing directory, generated-resource, clipboard, Mozilla, and platform conformance cases remain in place.

Readiness is tied to the exact settled background health endpoint, rather than only a 15-second timestamp. Startup and action no longer repeat the same bootstrap delay when that endpoint survives. Every action still challenges the bridge. Replacement fails old outstanding challenges, invalidates the readiness generation, and requires normal preparation. Unregistration completes pending observers with cancellation; old completions cannot dispatch a new action. Hover may prepare, while only a real action may authorize the existing persistent-context recovery path.

The original live timing helper preloaded popup content and slept four seconds before starting its timer. It now starts immediately before the real action, waits for actual popover presentation, and then waits for meaningful content. The separate close/reopen contract explicitly retains its intentional warm-up.

| Original click to meaningful popup content | Baseline | Candidate | Final source repeat |
| --- | ---: | ---: | ---: |
| Cold install, first action | 1,440 ms | 1,471 ms | 1,447 ms |
| Restored, 45 seconds idle, untouched first action | 1,482 ms | 911 ms | 708 ms |

These are individual lifecycle runs, not latency percentiles. The once-only 750 ms compatibility grace remains to protect delayed listener initialization; a responding bridge alone does not prove vendor initialization is finished. No vendor JavaScript, permissions, storage semantics, or mobile-extension availability changes in this pass. The pinned MV2 fixture does not reproduce MV3 worker eviction. Broader vendor workflows, long-run recovery, and page-load/theme timing are not certified by popup success.

## Extension metadata

Identity and selection now use authorized live Space IDs, transient IDs, or the existing detached snapshot. They no longer call the full runtime state projection merely to find a tab or selected Space. Native tab adapters retain their object identity; actual requested metadata still reads current loading/reader state and enforces assignment/access checks.

The existing operation-count contract failed before the change with 112, 412, and 2,012 page reads at 50, 200, and 1,000 tabs. It passes with zero at all three sizes. One Debug measurement, including adapter creation, fell from 6.06 to 2.85 ms at 1,000 tabs. The operation count is the durable result; that single duration is not a performance percentile. Full projections remain where callers actually need full snapshots.

## Validation and cleanup

- Final Mac contract run: **508 passed, eight opt-in tests skipped, zero failures**. Covers native motion/layout/drag behavior, page lifecycle, address editing/completion, extension controllers/preparation/health, Mozilla compatibility, tab/group movement, and scale fixtures.
- Final mobile contract run: **178 passed, zero failures or skips**, covering shared completion integration, navigation, root state, sidebar access, and reorder policy.
- Final live Firefox Dark Reader run: **one passed**, including both original cold action and persistent restoration/45-second idle. This is additional to the Mac contract batch.
- After the final actor-annotation cleanup, **18 Mac observer/presentation tests and 49 mobile transient-browsing tests passed**. A separate context-menu installation check also passed after removing its unused local binding; the assertion that the context loads remains.
- Optimized isolated Mac and Mobile Production builds passed, including final rebuilds after the warning cleanup. Those final build logs contain no Swift compiler warnings. Architecture, vertical structure, changed Swift formatting, version/release catalog, public-source hygiene, and whitespace checks passed.
- Temporary package timing tests and tab-enumeration prints were removed. The address benchmark/oracle and native measurement tools live only in the local artifact directory. Existing durable tests were extended instead of creating a test for each cache/helper. The heavy fixture's obsolete six-Space expectation now checks every template plus Daylight and supported scale limits.
- The shared split-card coordinate identifiers and extension diagnostic notification keys are explicitly nonisolated constants; registry/log mutation stays on the main actor. The mobile device-idiom helper explicitly runs on the main actor. This resolves the associated compiler warnings without changing frame ownership or presentation policy.
- Version remains the single **0.5.87** boundary, with appended release entries. `Documentation/ROADMAP.md` is user-owned and preserved.
- Handoff: the final isolated Mac app is open from `HandoffProducts/Crest Performance Soak.app`, restored to the regular 24-tab-per-Space demo. Mobile Production 0.5.87 was installed and launched on the connected iPhone 15 Pro Max. The new final pass was validated automatically; installation is not an additional physical-input acceptance capture. These changes form the 0.5.87 performance commit on local main.

## Scope after this pass

This pass delivers the measured address-completion, package-preparation, readiness, and metadata work in plan packages 7–9 and 12, alongside the earlier Space presentation and naming work. It does not claim full acceptance of every proposed budget in the original plan.

Further work should be separate, measured changes: narrow the remaining structural/selection publication and row observations; evaluate row virtualization with drag-source lifetime and mobile offscreen-promotion safeguards; split runtime assembly and other large owners at cohesive boundaries; and consolidate remaining shared page lifecycle/command behavior. The existing [implementation plan](implementation-plan.md) retains those directions. A blanket `.id` addition, eager mounting of every Space, vendor-specific readiness shortcuts, or another animation-curve experiment is not justified by this pass.

Remaining validation limits include physical vertical-scroll acceptance, mobile vertical frame traces, RTL touch presentation, demonstrated worker-eviction recovery, and longer multi-extension sessions. Automated scrolling does not certify physical trackpad feel, and successful builds/tests do not establish zero hitches.

## Reproducibility

Local artifact root: `/private/tmp/crest-performance-closeout-20260908/`. It contains source snapshots, standalone completion harness/oracle, package fixture, before/after preparation and enumeration logs, `.xcresult` bundles, optimized app/dSYM, and native scale captures. These temporary paths are evidence locations on this Mac, not shipped application dependencies or a permanent archive.

Source: local main based on `a33c6885` with the 0.5.87 performance changes. Final optimized Mac executable SHA-256: `a45fe76aa26d0f5caa378bb78232cc2796d354c0333f83527682624d2d452cc6`; matching executable/dSYM UUID: `FC0B5DE0-4C67-351D-AFE7-E804D6AB9896`. Mac measurements use the isolated `com.pauldavis.crest.performance-soak` bundle, macOS/Xcode 27 beta, and synthetic native input where explicitly indicated. The earlier matched vertical baseline is preserved under `/private/tmp/crest-vertical-scroll-20260908/`.
