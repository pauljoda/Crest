import Foundation

final class InMemoryBrowserExtensionUpdateMetadataPersistence:
    BrowserExtensionUpdateMetadataPersisting
{
    private var lastCheckedAt: Date?

    init(lastCheckedAt: Date? = nil) {
        self.lastCheckedAt = lastCheckedAt
    }

    func loadLastCheckedAt() -> Date? {
        lastCheckedAt
    }

    func saveLastCheckedAt(_ date: Date) {
        lastCheckedAt = date
    }
}
