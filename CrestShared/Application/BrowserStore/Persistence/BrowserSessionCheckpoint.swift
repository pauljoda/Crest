import Foundation

/// Immutable serialized parts supplied by the session owner. Native persistence
/// still owns the storage keys, unreadable-data recovery and favicon side store.
protocol BrowserSessionCheckpoint: AnyObject, Sendable {
    func coreData() -> Data?
    func historyData(in spaceID: SpaceID) -> Data?
}
