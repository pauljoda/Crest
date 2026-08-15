import Foundation

/// In-memory history double for tests, previews, and isolated launches.
///
/// It answers reads through the same
/// ``BrowserExtensionHistoryQueryPolicy`` the store-backed service uses, so a
/// test written against this double exercises the real query semantics. A scope
/// counts as resolvable only once it has been registered, which lets a test
/// reproduce the deleted-or-replaced Space case that makes the real adapter
/// refuse writes.
@MainActor
final class InMemoryBrowserExtensionHistoryStore: BrowserExtensionHistoryProviding {
    private typealias Subscribers = [UUID: AsyncStream<BrowserExtensionHistoryChange>.Continuation]

    /// The clock ``topSites(limit:in:)`` ranks against.
    var now: Date

    private var histories: [BrowserSpaceRuntimeAssignment: [BrowserHistoryEntry]]
    private var subscribers: [BrowserSpaceRuntimeAssignment: Subscribers] = [:]

    init(
        histories: [BrowserSpaceRuntimeAssignment: [BrowserHistoryEntry]] = [:],
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) {
        self.histories = histories
        self.now = now
    }

    /// Makes `scope` resolvable, seeded with `history`.
    func register(
        _ scope: BrowserSpaceRuntimeAssignment,
        history: [BrowserHistoryEntry] = []
    ) {
        histories[scope] = history
    }

    /// Makes `scope` stop resolving, as a deleted or replaced Space would.
    func unregister(_ scope: BrowserSpaceRuntimeAssignment) {
        histories.removeValue(forKey: scope)
        guard let continuations = subscribers.removeValue(forKey: scope) else {
            return
        }
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    /// The rows currently stored for `scope`, most-recent-first.
    func history(in scope: BrowserSpaceRuntimeAssignment) -> [BrowserHistoryEntry] {
        histories[scope] ?? []
    }

    func search(
        _ query: BrowserExtensionHistoryQuery,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionHistoryItem] {
        guard let history = histories[scope] else { return [] }
        return BrowserExtensionHistoryQueryPolicy.items(
            matching: query,
            in: history
        )
    }

    func visits(
        for url: URL,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionHistoryVisit] {
        guard let history = histories[scope] else { return [] }
        return BrowserExtensionHistoryQueryPolicy.visits(for: url, in: history)
    }

    func topSites(
        limit: Int,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionTopSite] {
        guard let history = histories[scope] else { return [] }
        return BrowserExtensionTopSitePolicy.topSites(
            from: history,
            limit: limit,
            now: now
        )
    }

    @discardableResult
    func addURL(
        _ url: URL,
        title: String?,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard var history = histories[scope],
            let normalizedURL = BrowserHistoryURL.normalized(url)
        else {
            return false
        }

        let resolvedTitle =
            title.flatMap { $0.isEmpty ? nil : $0 }
            ?? normalizedURL.host()
            ?? normalizedURL.absoluteString

        if let index = history.firstIndex(where: { $0.url == normalizedURL }) {
            var entry = history.remove(at: index)
            entry.title = resolvedTitle
            entry.lastVisitedAt = now
            entry.visitCount += 1
            history.insert(entry, at: 0)
        } else {
            history.insert(
                BrowserHistoryEntry(
                    url: normalizedURL,
                    title: resolvedTitle,
                    firstVisitedAt: now,
                    lastVisitedAt: now
                ),
                at: 0
            )
        }

        histories[scope] = history
        if let entry = history.first {
            publish(.visited(BrowserExtensionHistoryItem(entry)), to: scope)
        }
        return true
    }

    @discardableResult
    func deleteURL(
        _ url: URL,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard var history = histories[scope],
            let normalizedURL = BrowserHistoryURL.normalized(url)
        else {
            return false
        }

        let originalCount = history.count
        history.removeAll { $0.url == normalizedURL }
        guard history.count != originalCount else { return false }

        histories[scope] = history
        publish(.removed(urls: [normalizedURL]), to: scope)
        return true
    }

    @discardableResult
    func deleteRange(
        from startDate: Date,
        until endDate: Date,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard var history = histories[scope] else { return false }

        let removed = history.filter { entry in
            entry.lastVisitedAt >= startDate && entry.lastVisitedAt < endDate
        }
        guard !removed.isEmpty else { return false }

        history.removeAll { entry in
            entry.lastVisitedAt >= startDate && entry.lastVisitedAt < endDate
        }
        histories[scope] = history
        publish(
            history.isEmpty ? .removedAll : .removed(urls: removed.map(\.url)),
            to: scope
        )
        return true
    }

    @discardableResult
    func deleteAll(in scope: BrowserSpaceRuntimeAssignment) -> Bool {
        guard let history = histories[scope], !history.isEmpty else {
            return false
        }
        histories[scope] = []
        publish(.removedAll, to: scope)
        return true
    }

    func changes(
        in scope: BrowserSpaceRuntimeAssignment
    ) -> AsyncStream<BrowserExtensionHistoryChange> {
        let (stream, continuation) = AsyncStream<
            BrowserExtensionHistoryChange
        >.makeStream()

        guard histories[scope] != nil else {
            continuation.finish()
            return stream
        }

        let token = UUID()
        subscribers[scope, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.subscribers[scope]?.removeValue(forKey: token)
            }
        }
        return stream
    }

    private func publish(
        _ change: BrowserExtensionHistoryChange,
        to scope: BrowserSpaceRuntimeAssignment
    ) {
        guard let continuations = subscribers[scope] else { return }
        for continuation in continuations.values {
            continuation.yield(change)
        }
    }
}
