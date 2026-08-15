struct BrowserPasswordImportResult: Equatable, Sendable {
    let importedCount: Int
    let skippedCount: Int

    static let empty = BrowserPasswordImportResult(importedCount: 0, skippedCount: 0)
}
