import CoreGraphics
import Foundation
import ImageIO
import Synchronization

actor BrowserFaviconImageCache {
    // MARK: - Types

    private struct Storage: @unchecked Sendable {
        var entries: [BrowserFaviconImageCacheKey: (image: CGImage, tick: UInt64)] = [:]
        var tick: UInt64 = 0
    }

    // MARK: - Static Variables

    static let shared = BrowserFaviconImageCache()
    static let maximumCachedImageCount = 1024

    // MARK: - Variables

    private let decode: @Sendable (Data, Int) -> CGImage?
    private let storage = Mutex(Storage())
    private var requests = BrowserFaviconImageCacheRequestRegistry()

    // MARK: - Initializers

    init(
        decode: @escaping @Sendable (Data, Int) -> CGImage? =
            BrowserFaviconImageDecoder.decodeSynchronously
    ) {
        self.decode = decode
    }

    // MARK: - Actions - Reading

    /// Returns a previously decoded image synchronously without hopping to the
    /// cache actor, so scrolling rows avoid placeholder flashes and async task
    /// churn on cache hits.
    nonisolated func cachedImage(
        for payload: BrowserFaviconPayloadIdentity,
        maximumPixelSize: Int
    ) -> CGImage? {
        let clampedSize = min(
            max(1, maximumPixelSize),
            BrowserFaviconImageDecoder.maximumPixelSizeLimit
        )
        let key = BrowserFaviconImageCacheKey(
            payload: payload,
            maximumPixelSize: clampedSize
        )
        return storage.withLock { state in
            guard let entry = state.entries[key] else { return nil }
            state.tick &+= 1
            state.entries[key] = (entry.image, state.tick)
            return entry.image
        }
    }

    func image(
        for data: Data,
        payloadIdentity: BrowserFaviconPayloadIdentity? = nil,
        maximumPixelSize: Int
    ) async -> CGImage? {
        let clampedSize = min(
            max(1, maximumPixelSize),
            BrowserFaviconImageDecoder.maximumPixelSizeLimit
        )
        // Reuse the precomputed fingerprint when available; otherwise hash on
        // the cache actor rather than the main actor.
        let payload = payloadIdentity ?? BrowserFaviconPayloadIdentity(hashing: data)
        if let cached = cachedImage(for: payload, maximumPixelSize: clampedSize) {
            return cached
        }

        let key = BrowserFaviconImageCacheKey(
            payload: payload,
            maximumPixelSize: clampedSize
        )
        let lease = requests.lease(for: key) {
            let decode = decode
            return Task.detached(priority: .utility) {
                decode(data, clampedSize)
            }
        }

        let decodedImage = await lease.task.value
        guard requests.isCurrent(lease) else { return nil }
        guard requests.complete(lease, for: key) else {
            return cachedImage(for: payload, maximumPixelSize: clampedSize)
        }
        guard let decodedImage else { return nil }
        insert(decodedImage, for: key)
        return decodedImage
    }

    // MARK: - Actions - Changes

    func removeAll() {
        storage.withLock { state in
            state.entries.removeAll(keepingCapacity: true)
            state.tick = 0
        }
        for lease in requests.removeAll() {
            lease.task.cancel()
        }
    }

    private func insert(_ image: CGImage, for key: BrowserFaviconImageCacheKey) {
        storage.withLock { state in
            state.tick &+= 1
            state.entries[key] = (image, state.tick)
            if state.entries.count > Self.maximumCachedImageCount {
                let overflow = state.entries.count - Self.maximumCachedImageCount
                let evictedKeys = state.entries
                    .sorted { $0.value.tick < $1.value.tick }
                    .prefix(overflow)
                    .map(\.key)
                for evictedKey in evictedKeys {
                    state.entries[evictedKey] = nil
                }
            }
        }
    }
}
