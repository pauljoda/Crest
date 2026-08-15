import Foundation

actor BrowserExtensionIconDecoder<DecodedIcon: Sendable> {
    private typealias CacheKey = BrowserExtensionIconRequestIdentity

    private struct InFlightEntry: Sendable {
        let generation: UUID
        let task: Task<DecodedIcon?, Never>
        var waiterCount: Int
    }

    private enum CacheEntry: Sendable {
        case decoded(DecodedIcon)
        case unavailable

        var icon: DecodedIcon? {
            switch self {
            case .decoded(let icon):
                icon
            case .unavailable:
                nil
            }
        }
    }

    typealias Decode = @Sendable (Data, Int) async -> DecodedIcon?
    typealias CompletionBarrier = @Sendable () async -> Void

    static var maximumCachedIconCount: Int { 64 }

    private let maximumCacheEntryCount: Int
    private let decode: Decode
    private let completionBarrier: CompletionBarrier?
    private var cache: [CacheKey: CacheEntry] = [:]
    private var recency: [CacheKey] = []
    private var inFlight: [CacheKey: InFlightEntry] = [:]

    var cachedEntryCount: Int { cache.count }
    var inFlightRequestCount: Int { inFlight.count }
    var inFlightWaiterCount: Int {
        inFlight.values.reduce(0) { $0 + $1.waiterCount }
    }

    init<DecodingPort: BrowserExtensionIconDecoding>(
        cacheLimit: Int? = nil,
        decodingPort: DecodingPort,
        completionBarrier: CompletionBarrier? = nil
    ) where DecodingPort.DecodedIcon == DecodedIcon {
        maximumCacheEntryCount = min(
            max(0, cacheLimit ?? Self.maximumCachedIconCount),
            Self.maximumCachedIconCount
        )
        decode = decodingPort.decode
        self.completionBarrier = completionBarrier
    }

    func icon(for request: BrowserExtensionIconRequest) async -> DecodedIcon? {
        guard let payload = request.payload,
            payload.isValidForDecoding
        else {
            return nil
        }
        let key = request.identity

        if let cached = cache[key] {
            recordAccess(to: key)
            return cached.icon
        }

        let entry: InFlightEntry
        if var pending = inFlight[key] {
            pending.waiterCount += 1
            inFlight[key] = pending
            entry = pending
        } else {
            entry = InFlightEntry(
                generation: UUID(),
                task: Task.detached(priority: .utility) { [decode] in
                    await decode(payload.data, request.maximumPixelSize)
                },
                waiterCount: 1
            )
            inFlight[key] = entry
        }

        let icon = await entry.task.value
        if let completionBarrier {
            await completionBarrier()
        }
        guard inFlight[key]?.generation == entry.generation else {
            return icon
        }
        inFlight[key] = nil
        insert(
            icon.map(CacheEntry.decoded) ?? .unavailable,
            for: key
        )
        return icon
    }

    func removeAll() {
        cache.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
    }

    private func insert(_ entry: CacheEntry, for key: CacheKey) {
        guard maximumCacheEntryCount > 0 else { return }
        cache[key] = entry
        recordAccess(to: key)
        while cache.count > maximumCacheEntryCount,
            let leastRecent = recency.first
        {
            recency.removeFirst()
            cache[leastRecent] = nil
        }
    }

    private func recordAccess(to key: CacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
