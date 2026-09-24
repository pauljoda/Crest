import Foundation

@MainActor
final class BrowserPagePoolRegistry: BrowserSpaceDataDeleting {

    private final class WeakPool {
        weak var value: BrowserPagePool?

        init(_ value: BrowserPagePool) {
            self.value = value
        }
    }

    private final class WeakWindowRuntime {
        weak var browser: BrowserStore?
        weak var pages: BrowserPagePool?

        init(browser: BrowserStore, pages: BrowserPagePool) {
            self.browser = browser
            self.pages = pages
        }
    }

    private weak var spaceAccess: BrowserSpaceAccessController?
    private let closePreparation: (any BrowserPageClosePreparing)?
    private let primary: BrowserPagePool
    private var pools: [ObjectIdentifier: WeakPool] = [:]
    private var windowRuntimes: [BrowserWindowID: WeakWindowRuntime] = [:]
    private var spacesDeletingData: Set<SpaceID> = []

    init(primary: BrowserPagePool, spaceAccess: BrowserSpaceAccessController? = nil,
        closePreparation: (any BrowserPageClosePreparing)? = nil) {
        self.primary = primary
        self.spaceAccess = spaceAccess
        self.closePreparation = closePreparation
    }

    func register(_ pool: BrowserPagePool) {
        pools[ObjectIdentifier(pool)] = WeakPool(pool)
    }

    func register(
        _ pool: BrowserPagePool,
        browser: BrowserStore,
        for windowID: BrowserWindowID
    ) {
        register(pool)
        browser.family.pageDismissalAuthorizer = self
        windowRuntimes[windowID] = WeakWindowRuntime(
            browser: browser,
            pages: pool
        )
    }

    func unregister(_ pool: BrowserPagePool) {
        pools.removeValue(forKey: ObjectIdentifier(pool))
    }

    func unregister(_ pool: BrowserPagePool, for windowID: BrowserWindowID) {
        unregister(pool)
        windowRuntimes.removeValue(forKey: windowID)
    }

    func runtime(for windowID: BrowserWindowID) -> BrowserPagePoolWindowRuntime? {
        guard let runtime = windowRuntimes[windowID],
            let browser = runtime.browser,
            let pages = runtime.pages
        else {
            windowRuntimes.removeValue(forKey: windowID)
            return nil
        }
        return BrowserPagePoolWindowRuntime(browser: browser, pages: pages)
    }

    /// Releases every window's pages in the Space, then its data. The Space's
    /// deletion is already recorded in the session, so the core opens no new
    /// page there while this runs.
    func deleteData(for space: BrowserSpace) async throws {
        guard spacesDeletingData.insert(space.id).inserted else { return }
        defer { spacesDeletingData.remove(space.id) }

        pools = pools.filter { $0.value.value != nil }
        let livePools = [primary] + pools.values.compactMap(\.value).filter { $0 !== primary }
        for pool in livePools where pool !== primary {
            await pool.releaseWindowRuntime(for: space)
        }
        try await primary.deleteData(for: space)
    }
}

extension BrowserPagePoolRegistry: BrowserPageDismissalAuthorizing {
    func performDismissal(of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
        operation: @escaping @MainActor () -> Bool) -> Bool {
        func ownedPages() -> [BrowserPage] {
            var seen = Set<ObjectIdentifier>()
            return windowRuntimes.values.compactMap { runtime -> BrowserPagePool? in
                runtime.browser?.family === browser.family ? runtime.pages : nil
            }.flatMap { pool in assignments.compactMap { pool.residentPage(matching: $0) } }
                .filter { seen.insert(ObjectIdentifier($0)).inserted }
        }
        func isAvailable() -> Bool {
            assignments.allSatisfy { assignment in
                guard let space = browser.space(matching: BrowserSpaceRuntimeAssignment(
                    spaceID: assignment.spaceID, profileID: assignment.profileID)),
                    !spacesDeletingData.contains(space.id) else { return false }
                return spaceAccess?.isLocked(space) != true
            }
        }
        guard isAvailable() else { return false }
        let pages = ownedPages()
        guard let closePreparation,
            pages.contains(where: { $0.pageEngine.registration.supports(.beforeUnload) })
        else { return operation() }
        let identities = Set(pages.map { ObjectIdentifier($0) })
        var committed = false
        closePreparation.prepareToClose(pages.map { $0.pageEngine }) { [weak self, weak browser] allowed in
            guard let self, let browser, allowed, isAvailable(),
                Set(ownedPages().map { ObjectIdentifier($0) }) == identities else { return }
            committed = operation()
            guard committed else { return }
            for runtime in self.windowRuntimes.values where runtime.browser?.family === browser.family {
                guard let store = runtime.browser, let pool = runtime.pages else { continue }
                pool.reconcile(session: store.session)
                pool.select(session: store.presented)
            }
        }
        return committed
    }
}
