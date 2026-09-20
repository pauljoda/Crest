import AppKit
import Observation
import WebKit

/// Normal windows share page ownership while their pools retain independent
/// selection. A temporary workspace receives its own store.
@Observable
@MainActor
final class BrowserPageRuntimeStore {
    private struct WeakPool {
        weak var value: BrowserPagePool?
    }

    @ObservationIgnored var spacesReleasingData: Set<SpaceID> = []
    @ObservationIgnored var spacesDeletingData: Set<SpaceID> = []
    @ObservationIgnored var blockedSpaces: Set<SpaceID> = []
    @ObservationIgnored var runtimes: [TabID: BrowserTabRuntime] = [:]
    @ObservationIgnored var inactiveSinceByTabID: [TabID: Date] = [:]
    @ObservationIgnored var memoryPressureTask: Task<Void, Never>?
    @ObservationIgnored var memoryPressureCoalescer = BrowserMemoryPressureCoalescer()
    @ObservationIgnored private var pools: [BrowserWindowID: WeakPool] = [:]
    @ObservationIgnored private var presentations: [BrowserWindowID: [TabID]] = [:]
    @ObservationIgnored private var focusOrder: [BrowserWindowID: Int] = [:]
    @ObservationIgnored private var focusSequence = 0
    let tabState: BrowserTabStateCoordinator
    let nativeTabs = BrowserNativeTabStore()
    var revision = 0
    var publishesPageMetadataCentrally = false

    init(archive: (any BrowserTabStateArchiving)? = nil) {
        tabState = BrowserTabStateCoordinator(archive: archive)
    }

    var registeredPools: [BrowserPagePool] { pools.values.compactMap(\.value) }

    var presentedTabIDs: Set<TabID> {
        Set(presentations.values.joined())
    }

    func isPresented(_ tabID: TabID, outside windowID: BrowserWindowID) -> Bool {
        presentations.contains { $0.key != windowID && $0.value.contains(tabID) }
    }

    func register(_ pool: BrowserPagePool) {
        pools[pool.windowID] = WeakPool(value: pool)
    }

    func updatePresentation(of pool: BrowserPagePool) {
        register(pool)
        presentations[pool.windowID] = pool.presentedTabIDs
        for tabID in pool.presentedTabIDs {
            if let runtime = runtimes[tabID],
                runtime.presentationWindowID == nil || pool.isWindowFocused
            {
                claim(tabID, for: pool)
            }
            inactiveSinceByTabID[tabID] = nil
        }
        for (tabID, runtime) in runtimes
        where runtime.presentationWindowID == pool.windowID && !pool.presentedTabIDs.contains(tabID) {
            reassignPresentation(tabID, excluding: pool.windowID)
        }
    }

    func focus(_ pool: BrowserPagePool) {
        for other in registeredPools where other !== pool {
            other.setWindowFocused(false)
        }
        focusSequence &+= 1
        focusOrder[pool.windowID] = focusSequence
        updatePresentation(of: pool)
    }

    func claim(_ tabID: TabID, for pool: BrowserPagePool) {
        guard pool.presentedTabIDs.contains(tabID), let runtime = runtimes[tabID] else { return }
        guard runtime.presentationWindowID != pool.windowID else {
            pool.bindRuntimeRouting(runtime, tabID: tabID)
            return
        }
        if runtime.presentationWindowID != nil {
            captureSnapshot(of: runtime)
            runtime.page.focusRestoration.captureBeforeDeparture()
            runtime.page.focusRestoration.requestRestoration()
        }
        inactiveSinceByTabID[tabID] = nil
        runtime.presentationWindowID = pool.windowID
        runtime.routingWindowID = pool.windowID
        pool.bindRuntimeRouting(runtime, tabID: tabID)
        revision &+= 1
    }

    func unregister(_ pool: BrowserPagePool) {
        presentations.removeValue(forKey: pool.windowID)
        pools.removeValue(forKey: pool.windowID)
        focusOrder.removeValue(forKey: pool.windowID)
        for (tabID, runtime) in runtimes where runtime.routingWindowID == pool.windowID {
            reassignPresentation(tabID, excluding: pool.windowID)
            if let fallback = mostRecentPool(among: Set(pools.keys)) {
                if runtime.presentationWindowID == nil {
                    runtime.routingWindowID = fallback.windowID
                    fallback.bindRuntimeRouting(runtime, tabID: tabID)
                }
            }
        }
        revision &+= 1
    }

    func install(_ runtime: BrowserTabRuntime, for tabID: TabID, from pool: BrowserPagePool) {
        runtimes[tabID] = runtime
        runtime.store = self
        runtime.tabID = tabID
        runtime.routingWindowID = pool.windowID
        pool.bindRuntimeRouting(runtime, tabID: tabID)
        runtime.observeCurrentPage()
        updatePresentation(of: pool)
    }

    func removePresentation(of tabID: TabID) {
        for pool in registeredPools {
            pool.removeTransferredPresentation(tabID)
        }
    }

    func pageDidChange(
        _ runtime: BrowserTabRuntime, previous: BrowserBackgroundPageSnapshot?, current: BrowserBackgroundPageSnapshot,
        currentPageChanged: Bool = false
    ) {
        guard let tabID = runtime.tabID, runtimes[tabID] === runtime else { return }
        if current.completedNavigationCount > 0 || current.hasNavigationFailure
            || (previous?.isLoading == true && !current.isLoading)
        {
            if !presentedTabIDs.contains(tabID), inactiveSinceByTabID[tabID] == nil {
                inactiveSinceByTabID[tabID] = .now
            }
        }
        guard publishesPageMetadataCentrally, previous != current || currentPageChanged,
            let owner = runtime.routingWindowID.flatMap({ pools[$0]?.value }) ?? mostRecentPool(among: Set(pools.keys))
        else { return }
        owner.publishRuntimePageUpdate(runtime, tabID: tabID, previous: previous, current: current)
    }

    private func reassignPresentation(_ tabID: TabID, excluding windowID: BrowserWindowID) {
        guard let runtime = runtimes[tabID] else { return }
        let candidates = Set(
            presentations.compactMap { id, tabs in
                id != windowID && tabs.contains(tabID) ? id : nil
            })
        if let next = mostRecentPool(among: candidates) {
            claim(tabID, for: next)
        } else {
            runtime.presentationWindowID = nil
            inactiveSinceByTabID[tabID] = inactiveSinceByTabID[tabID] ?? .now
            revision &+= 1
        }
    }

    private func mostRecentPool(among ids: Set<BrowserWindowID>) -> BrowserPagePool? {
        ids.compactMap { pools[$0]?.value }.max {
            (focusOrder[$0.windowID] ?? 0) < (focusOrder[$1.windowID] ?? 0)
        }
    }

    private func captureSnapshot(of runtime: BrowserTabRuntime) {
        runtime.snapshotGeneration &+= 1
        let generation = runtime.snapshotGeneration
        runtime.page.captureViewport { [weak self, weak runtime] image in
            MainActor.assumeIsolated {
                guard let self, let runtime, runtime.store === self, runtime.snapshotGeneration == generation else {
                    return
                }
                if let image { runtime.snapshot = image }
                self.revision &+= 1
            }
        }
    }
}

@MainActor
final class BrowserPageWindowRouting {
    weak var pool: BrowserPagePool?

    init(pool: BrowserPagePool) { self.pool = pool }
}

@MainActor
final class BrowserPageProfileDataStores {
    let serverTrustOverrides = BrowserServerTrustOverrideStore()
    var blockedSpaces: Set<SpaceID> = []
    var ephemeral: [UUID: WKWebsiteDataStore] = [:]
}
