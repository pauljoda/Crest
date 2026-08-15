struct BrowserBookmarkHTMLWriter {
    private(set) var output = ""
    private var encodedByteCount = 0

    mutating func append(_ value: String) throws {
        encodedByteCount += value.utf8.count
        guard encodedByteCount <= BrowserBookmarkMigration.maximumEncodedByteCount else {
            throw BrowserBookmarkMigrationError.fileTooLarge
        }
        output.append(value)
    }
}
