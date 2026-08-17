import Foundation

protocol BrowserExtensionUpdateMetadataPersisting: AnyObject {
    func loadLastCheckedAt() -> Date?
    func saveLastCheckedAt(_ date: Date)
}
