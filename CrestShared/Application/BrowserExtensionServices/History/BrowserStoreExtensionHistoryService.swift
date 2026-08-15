import Foundation
import Observation

/// Serves emulated `chrome.history` and `chrome.topSites` traffic from Crest's
/// per-Space browsing history.
///
/// Crest has no history database and no history change notification: history is
/// an array on each `BrowserSpace`, and `BrowserStore` republishes the whole
/// session whenever anything in it changes. Change events are therefore derived
/// rather than received — the service snapshots the Space's history when an
/// extension first subscribes, then re-diffs it whenever Observation reports
/// that the session moved. That keeps `onVisited` working for ordinary browsing
/// (which never goes through this service) without polling, at the cost of
/// coalescing several visits that land between two observation ticks into one
/// event per URL.
@MainActor
final class BrowserStoreExtensionHistoryService: BrowserExtensionHistoryProviding {
    private typealias Subscribers = [UUID: AsyncStream<BrowserExtensionHistoryChange>.Continuation]

    private let store: BrowserStore
    private let now: @MainActor () -> Date
    private var subscribers: [BrowserSpaceRuntimeAssignment: Subscribers] = [:]
    private var snapshots: [BrowserSpaceRuntimeAssignment: [BrowserHistoryEntry]] = [:]
    private var isObserving = false

    init(store: BrowserStore, now: @escaping @MainActor () -> Date = { .now }) {
        self.store = store
        self.now = now
    }

    // MARK: - Reads

    func search(
        _ query: BrowserExtensionHistoryQuery,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionHistoryItem] {
        guard let space = store.space(matching: scope) else { return [] }
        return BrowserExtensionHistoryQueryPolicy.items(
            matching: query,
            in: space.history
        )
    }

    func visits(
        for url: URL,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionHistoryVisit] {
        guard let space = store.space(matching: scope) else { return [] }
        return BrowserExtensionHistoryQueryPolicy.visits(
            for: url,
            in: space.history
        )
    }

    func topSites(
        limit: Int,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> [BrowserExtensionTopSite] {
        guard let space = store.space(matching: scope) else { return [] }
        return BrowserExtensionTopSitePolicy.topSites(
            from: space.history,
            limit: limit,
            now: now()
        )
    }

    // MARK: - Writes

    @discardableResult
    func addURL(
        _ url: URL,
        title: String?,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard BrowserHistoryURL.normalized(url) != nil else { return false }
        return store.recordVisit(url: url, title: title, matching: scope)
    }

    @discardableResult
    func deleteURL(
        _ url: URL,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        store.deleteHistory(for: url, matching: scope)
    }

    @discardableResult
    func deleteRange(
        from startDate: Date,
        until endDate: Date,
        in scope: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        store.deleteHistory(from: startDate, until: endDate, matching: scope)
    }

    @discardableResult
    func deleteAll(in scope: BrowserSpaceRuntimeAssignment) -> Bool {
        store.clearHistory(matching: scope)
    }

    // MARK: - Change events

    func changes(
        in scope: BrowserSpaceRuntimeAssignment
    ) -> AsyncStream<BrowserExtensionHistoryChange> {
        let (stream, continuation) = AsyncStream<
            BrowserExtensionHistoryChange
        >.makeStream()

        guard let space = store.space(matching: scope) else {
            continuation.finish()
            return stream
        }

        let token = UUID()
        snapshots[scope] = space.history
        subscribers[scope, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.removeSubscriber(token, for: scope)
            }
        }
        startObservingIfNeeded()
        return stream
    }

    private func startObservingIfNeeded() {
        guard !isObserving, !subscribers.isEmpty else { return }
        isObserving = true
        observeSession()
    }

    /// Observation fires once per change, so the tracking closure re-arms
    /// itself. The work hops to the next main-actor turn because `onChange`
    /// runs *before* the mutation lands.
    private func observeSession() {
        withObservationTracking {
            _ = store.sessionRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isObserving else { return }
                self.publishPendingChanges()
                self.observeSession()
            }
        }
    }

    private func publishPendingChanges() {
        for (scope, continuations) in subscribers {
            guard let space = store.space(matching: scope) else {
                for continuation in continuations.values {
                    continuation.finish()
                }
                subscribers.removeValue(forKey: scope)
                snapshots.removeValue(forKey: scope)
                continue
            }

            let previous = snapshots[scope] ?? []
            let current = space.history
            snapshots[scope] = current

            for change in Self.changes(from: previous, to: current) {
                for continuation in continuations.values {
                    continuation.yield(change)
                }
            }
        }
        if subscribers.isEmpty { isObserving = false }
    }

    private func removeSubscriber(
        _ token: UUID,
        for scope: BrowserSpaceRuntimeAssignment
    ) {
        subscribers[scope]?.removeValue(forKey: token)
        if subscribers[scope]?.isEmpty == true {
            subscribers.removeValue(forKey: scope)
            snapshots.removeValue(forKey: scope)
        }
        if subscribers.isEmpty { isObserving = false }
    }

    /// Diffs two history snapshots into `chrome.history` events.
    static func changes(
        from previous: [BrowserHistoryEntry],
        to current: [BrowserHistoryEntry]
    ) -> [BrowserExtensionHistoryChange] {
        let previousByURL = Dictionary(
            previous.map { ($0.url, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentURLs = Set(current.map(\.url))

        var changes: [BrowserExtensionHistoryChange] = []
        for entry in current {
            guard let earlier = previousByURL[entry.url] else {
                changes.append(.visited(BrowserExtensionHistoryItem(entry)))
                continue
            }
            if earlier.visitCount != entry.visitCount
                || earlier.lastVisitedAt != entry.lastVisitedAt
            {
                changes.append(.visited(BrowserExtensionHistoryItem(entry)))
            }
        }

        let removedURLs = previous.map(\.url).filter { !currentURLs.contains($0) }
        if !removedURLs.isEmpty {
            changes.append(
                current.isEmpty ? .removedAll : .removed(urls: removedURLs)
            )
        }
        return changes
    }
}
