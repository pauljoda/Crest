import Foundation

enum BrowserDownloadTransfer {
    static func stagingURL(
        itemID: UUID,
        suggestedFilename: String,
        directory: URL
    ) -> URL {
        let safeFilename = BrowserDownloadDestination.safeFilename(
            from: suggestedFilename
        )
        return directory.appendingPathComponent(
            "\(itemID.uuidString)-\(safeFilename)"
        )
    }

    static func finish(
        from stagingURL: URL,
        to destinationURL: URL,
        quarantine: BrowserDownloadQuarantine? = nil,
        fileManager: FileManager = .default
    ) throws {
        try coordinatedMove(from: stagingURL, to: destinationURL, fileManager: fileManager)
        guard let quarantine else { return }

        do {
            try BrowserPlatformDownloadQuarantine.apply(
                quarantine,
                to: destinationURL
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    /// A folder the person chose can belong to a file provider, such as
    /// iCloud Drive, which sees and syncs a new file only through a
    /// coordinated write.
    private static func coordinatedMove(
        from stagingURL: URL, to destinationURL: URL, fileManager: FileManager
    ) throws {
        var coordinationError: NSError?
        var moveError: (any Error)?
        NSFileCoordinator().coordinate(
            writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.moveItem(at: stagingURL, to: coordinatedURL)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
    }
}
