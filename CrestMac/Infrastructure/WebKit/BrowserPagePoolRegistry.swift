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

    private let primary: BrowserPagePool
    private var pools: [ObjectIdentifier: WeakPool] = [:]
    private var windowRuntimes: [BrowserWindowID: WeakWindowRuntime] = [:]
    private var spacesDeletingData: Set<SpaceID> = []

    init(primary: BrowserPagePool) {
        self.primary = primary
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

    func deleteData(for space: BrowserSpace) async throws {
        guard spacesDeletingData.insert(space.id).inserted else { return }
        defer { spacesDeletingData.remove(space.id) }

        pools = pools.filter { $0.value.value != nil }
        let livePools = pools.values.compactMap(\.value)
        for pool in livePools where pool !== primary {
            await pool.releaseWindowRuntime(for: space)
        }
        try await primary.deleteData(for: space)
    }
}
