#if CREST_PERFORMANCE_HARNESS
    import AppKit
    import OSLog
    import SwiftUI

    /// S6.4 spike, performance builds only: shows the spike sidebar over the
    /// performance soak's heavy session in a window of its own and measures,
    /// in a Release build under Instruments, how long each kind of change takes
    /// from its drain to the Core Animation commit that shows it, a storm of
    /// title reports, and a whole workspace arriving again. It runs when the
    /// launch names a file for its results, writes them there and exits.
    @MainActor
    final class ReadModelSpikeRun {
        // MARK: - Types

        /// One measured series, in milliseconds.
        struct Series: Codable {
            /// A 120 Hz frame, in milliseconds.
            private static let frameBudget = 1_000.0 / 120

            let name: String
            let count: Int
            let p50: Double
            let p90: Double
            let p99: Double
            let maximum: Double
            let overFrame: Int
            /// The part of each run spent before the drain returned, when timed.
            let appliedP50: Double?
            let appliedP99: Double?
            /// The spike views' body evaluations per run, by kind: the most and the mean.
            let bodyMaxima: [String: Int]?
            let bodyMeans: [String: Double]?

            init(
                name: String, milliseconds: [Double], applied: [Double] = [],
                bodies: [[ReadModelSpikeBody: Int]] = []
            ) {
                let sorted = milliseconds.sorted()
                let appliedSorted = applied.sorted()
                self.name = name
                count = sorted.count
                p50 = Self.percentile(0.5, of: sorted)
                p90 = Self.percentile(0.9, of: sorted)
                p99 = Self.percentile(0.99, of: sorted)
                maximum = sorted.last ?? 0
                overFrame = sorted.filter { $0 > Self.frameBudget }.count
                appliedP50 = applied.isEmpty ? nil : Self.percentile(0.5, of: appliedSorted)
                appliedP99 = applied.isEmpty ? nil : Self.percentile(0.99, of: appliedSorted)
                let kinds = ReadModelSpikeBody.allCases
                bodyMaxima =
                    bodies.isEmpty
                    ? nil
                    : Dictionary(
                        uniqueKeysWithValues: kinds.map { kind in
                            (kind.rawValue, bodies.map { $0[kind] ?? 0 }.max() ?? 0)
                        })
                bodyMeans =
                    bodies.isEmpty
                    ? nil
                    : Dictionary(
                        uniqueKeysWithValues: kinds.map { kind in
                            (kind.rawValue, Double(bodies.map { $0[kind] ?? 0 }.reduce(0, +)) / Double(bodies.count))
                        })
            }

            private static func percentile(_ fraction: Double, of sorted: [Double]) -> Double {
                sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
            }
        }

        /// When one part of the run started and ended, to find its hitches in a trace.
        struct Phase: Codable {
            let name: String
            let start: Date
            let end: Date
        }

        /// What the run writes: its series and its phases.
        struct Report: Codable {
            let series: [Series]
            let phases: [Phase]
        }

        // MARK: - Static Variables

        private static let outputKey = "CREST_READ_MODEL_SPIKE_OUTPUT"
        /// Seconds to wait before measuring, long enough for Instruments to attach.
        private static let delayKey = "CREST_READ_MODEL_SPIKE_DELAY"
        /// Set to make every row at once, as the iPad sidebar does.
        private static let eagerKey = "CREST_READ_MODEL_SPIKE_EAGER"
        /// Set to measure only the edits whose names contain it, this many times each.
        private static let onlyKey = "CREST_READ_MODEL_SPIKE_ONLY"
        private static let runsKey = "CREST_READ_MODEL_SPIKE_RUNS"
        private static let signposter = OSSignposter(subsystem: "com.pauldavis.crest", category: .pointsOfInterest)
        private static var current: ReadModelSpikeRun?

        // MARK: - Variables

        private let output: URL
        private let delay: Duration
        private let isLazy: Bool
        private let bench: ReadModelSpikeBench
        private var windows: [NSWindow] = []
        private var series: [Series] = []
        private var phases: [Phase] = []
        private let only: String?
        private let runs: Int

        // MARK: - Initializers

        private init(output: URL, delay: Duration, isLazy: Bool, only: String?, runs: Int) {
            self.output = output
            self.delay = delay
            self.isLazy = isLazy
            self.only = only
            self.runs = runs
            guard
                let session = BrowserPerformanceSoakFixture.makeSession(
                    baseURLString: "http://127.0.0.1:8080/", rawTabCount: "500", isHeavy: true, runID: "spike")
            else { preconditionFailure("The soak fixture made no session.") }
            bench = ReadModelSpikeBench(session: session)
        }

        // MARK: - Actions - Running

        /// Starts the run when the launch names a file for its results.
        static func startIfRequested() {
            let environment = ProcessInfo.processInfo.environment
            guard let path = environment[outputKey] else { return }
            let seconds = environment[delayKey].flatMap(Int.init) ?? 2
            let run = ReadModelSpikeRun(
                output: URL(fileURLWithPath: path), delay: .seconds(seconds), isLazy: environment[eagerKey] == nil,
                only: environment[onlyKey], runs: environment[runsKey].flatMap(Int.init) ?? 100)
            current = run
            Task { await run.start() }
        }

        private func start() async {
            windows.append(
                show(
                    ReadModelSpikeSidebar(
                        workspace: bench.workspace, space: bench.space, window: bench.window, outline: bench.outline,
                        state: bench.core.state, isLazy: isLazy),
                    title: "Read model spike", origin: CGPoint(x: 40, y: 80)))
            try? await Task.sleep(for: delay)
            measureItems()
            let edits = ReadModelSpikeEdit.all.filter { edit in only.map { edit.name.contains($0) } ?? true }
            for edit in edits { await measure(edit, as: edit.name) }
            if only == nil { await storm(as: "Storm, 50 tabs x 10 titles/s") }
            // Without the Swift session copy, which S6.7 deletes, each change
            // reaches only the core and the read model.
            bench.core.state.sessionCopies.removeAll()
            for edit in edits { await measure(edit, as: "\(edit.name), no copy") }
            if only == nil {
                await storm(as: "Storm, 50 tabs x 10 titles/s, no copy")
                await reopen()
            }
            write()
            // The session lives only in memory, so nothing waits on a quit.
            exit(0)
        }

        private func measure(_ edit: ReadModelSpikeEdit, as name: String) async {
            let started = Date()
            defer { phases.append(Phase(name: name, start: started, end: Date())) }
            let runs = edit.name == ReadModelSpikeEdit.firstFavicon.name ? min(runs, bench.pages.count) : runs
            var durations: [Double] = []
            var applied: [Double] = []
            var bodies: [[ReadModelSpikeBody: Int]] = []
            for run in 0..<runs {
                edit.prepare?(bench, run + series.count * 1_000)
                _ = await nextCommit()
                ReadModelSpikeBodyCount.reset()
                let interval = Self.signposter.beginInterval("Edit", "\(name, privacy: .public)")
                let start = ContinuousClock.now
                edit.perform(bench, run + series.count * 1_000)
                let performed = ContinuousClock.now
                let committed = await nextCommit()
                Self.signposter.endInterval("Edit", interval)
                durations.append(Self.milliseconds(start.duration(to: committed)))
                applied.append(Self.milliseconds(start.duration(to: performed)))
                bodies.append(ReadModelSpikeBodyCount.counts)
                try? await Task.sleep(for: .milliseconds(12))
            }
            series.append(Series(name: name, milliseconds: durations, applied: applied, bodies: bodies))
        }

        /// Ten seconds in which each of 50 tabs reports a new title ten times
        /// a second, the reports of each tenth of a second drained together.
        private func storm(as name: String) async {
            let started = Date()
            defer { phases.append(Phase(name: name, start: started, end: Date())) }
            let pages = Array(bench.pages.prefix(50))
            var durations: [Double] = []
            var applied: [Double] = []
            let interval = Self.signposter.beginInterval("Storm")
            let stormStart = ContinuousClock.now
            var tick = 0
            while stormStart.duration(to: .now) < .seconds(10) {
                let start = ContinuousClock.now
                for page in pages { bench.report(page, title: "Storm \(tick)", drains: false) }
                bench.core.drain()
                applied.append(Self.milliseconds(start.duration(to: .now)))
                let committed = await nextCommit()
                durations.append(Self.milliseconds(start.duration(to: committed)))
                tick += 1
                try? await Task.sleep(until: stormStart + .milliseconds(100 * tick), clock: .continuous)
            }
            Self.signposter.endInterval("Storm", interval)
            series.append(Series(name: name, milliseconds: durations, applied: applied))
        }

        /// A read model of its own receives the session whole: new, again
        /// unchanged, and again with every tab retitled; then once more with a
        /// sidebar showing it, timed to the commit that shows the new titles.
        private func reopen() async {
            let first = bench.opening.session.spaces[0]
            let single = WorkspaceOpened(
                workspaceID: UUID(), kind: bench.opening.kind,
                session: SessionState(
                    spaces: [first], defaultSpaceID: first.id, disposableSeedMarker: nil, spaceDeletions: [],
                    appPreferences: nil))
            let whole = bench.opening
            for (name, opening) in [
                ("500 tabs", single), ("\(whole.session.spaces.count * first.tabs.count) tabs", whole),
            ] {
                let state = CoreState()
                series.append(
                    Series(name: "Reopen \(name), new", milliseconds: [Self.time { Self.apply(opening, to: state) }]))
                series.append(
                    Series(
                        name: "Reopen \(name), unchanged", milliseconds: [Self.time { Self.apply(opening, to: state) }])
                )
                let retitled = Self.retitled(opening, "*")
                series.append(
                    Series(
                        name: "Reopen \(name), retitled", milliseconds: [Self.time { Self.apply(retitled, to: state) }])
                )
            }
            let state = CoreState()
            Self.apply(single, to: state)
            guard let workspace = state.workspaces[single.workspaceID], let space = workspace.spaces.model(first.id)
            else {
                return
            }
            let outline = ReadModelSpikeOutline(space: space, workspaceID: workspace.id)
            windows.append(
                show(
                    ReadModelSpikeSidebar(
                        workspace: workspace, space: space, window: bench.window, outline: outline, state: state),
                    title: "Reopened", origin: CGPoint(x: 360, y: 80)))
            try? await Task.sleep(for: .seconds(1))
            _ = await nextCommit()
            let retitled = Self.retitled(single, "+")
            let interval = Self.signposter.beginInterval("Reopen")
            let start = ContinuousClock.now
            Self.apply(retitled, to: state)
            outline.receive([.workspaceOpened(retitled)])
            let committed = await nextCommit()
            Self.signposter.endInterval("Reopen", interval)
            series.append(
                Series(
                    name: "Reopen 500 tabs, retitled, shown to commit",
                    milliseconds: [Self.milliseconds(start.duration(to: committed))]))
        }

        /// What building the list's items costs alone, for the Space's rows.
        private func measureItems() {
            var durations: [Double] = []
            var count = 0
            for _ in 0..<100 {
                durations.append(
                    Self.time {
                        count =
                            ReadModelSpikeList.items(
                                space: bench.space, window: bench.window, outline: bench.outline,
                                state: bench.core.state
                            ).count
                    })
            }
            series.append(Series(name: "List items, \(count) items", milliseconds: durations))
        }

        private func write() {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try encoder.encode(Report(series: series, phases: phases)).write(to: output)
            } catch {
                preconditionFailure("The spike could not write its results: \(error)")
            }
        }

        // MARK: - Actions - Support

        private func show(_ view: some View, title: String, origin: CGPoint) -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(origin: origin, size: CGSize(width: 300, height: 900)), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.orderFrontRegardless()
            return window
        }

        /// Resolves at the end of the main run loop's turn, once Core Animation
        /// has committed what the turn drew, with the time it got there.
        private func nextCommit() async -> ContinuousClock.Instant {
            await withCheckedContinuation { continuation in
                let observer = CFRunLoopObserverCreateWithHandler(
                    nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
                ) { observer, _ in
                    CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
                    continuation.resume(returning: ContinuousClock.now)
                }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }

        private static func apply(_ opening: WorkspaceOpened, to state: CoreState) {
            let change = Change.workspaceOpened(opening)
            state.apply(change)
            state.finishBatch([change])
        }

        private static func time(_ body: () -> Void) -> Double {
            let start = ContinuousClock.now
            body()
            return milliseconds(start.duration(to: .now))
        }

        private static func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        }

        /// The session with every tab's title and display title ending in `mark`.
        private static func retitled(_ opening: WorkspaceOpened, _ mark: String) -> WorkspaceOpened {
            let session = opening.session
            let spaces = session.spaces.map { space in
                SpaceState(
                    id: space.id, profileID: space.profileID, settings: space.settings, folders: space.folders,
                    tabs: space.tabs.map { tab in
                        TabState(
                            id: tab.id, title: tab.title + mark, url: tab.url, nativeContent: tab.nativeContent,
                            savedURL: tab.savedURL, symbol: tab.symbol, faviconURL: tab.faviconURL,
                            iconAccent: tab.iconAccent, storedIconMode: tab.storedIconMode, placement: tab.placement,
                            folderID: tab.folderID, splitGroupID: tab.splitGroupID,
                            lastActivatedAt: tab.lastActivatedAt, positionModifiedAt: tab.positionModifiedAt,
                            customTitle: tab.customTitle, titleModifiedAt: tab.titleModifiedAt,
                            keepsPageLoaded: tab.keepsPageLoaded, iconMode: tab.iconMode,
                            displayTitle: tab.displayTitle + mark, isAwayFromSavedAddress: tab.isAwayFromSavedAddress,
                            pageIconIsCurrent: tab.pageIconIsCurrent)
                    },
                    splitGroups: space.splitGroups, archivedTabs: space.archivedTabs, history: space.history,
                    sidebar: space.sidebar)
            }
            return WorkspaceOpened(
                workspaceID: opening.workspaceID, kind: opening.kind,
                session: SessionState(
                    spaces: spaces, defaultSpaceID: session.defaultSpaceID,
                    disposableSeedMarker: session.disposableSeedMarker, spaceDeletions: session.spaceDeletions,
                    appPreferences: session.appPreferences))
        }
    }
#endif
