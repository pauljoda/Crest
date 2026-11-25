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

    /// Moves the finished file at `stagingURL` in at `destinationURL` and
    /// returns where it went, which is `destinationURL` unless the move's
    /// coordinator sent the file elsewhere.
    @discardableResult
    static func finish(
        from stagingURL: URL,
        to destinationURL: URL,
        quarantine: BrowserDownloadQuarantine? = nil
    ) async throws -> URL {
        let placedURL = try await CoordinatedMove(to: destinationURL).run(from: stagingURL)
        guard let quarantine else { return placedURL }

        do {
            try BrowserPlatformDownloadQuarantine.apply(
                quarantine,
                to: placedURL
            )
        } catch {
            try? FileManager.default.removeItem(at: placedURL)
            throw error
        }
        return placedURL
    }

    /// Moves a finished file in as a coordinated write: a folder the person
    /// chose can belong to a file provider, such as iCloud Drive, which sees
    /// and syncs a new file only through one. The provider can take as long
    /// as it likes to grant the write, so the move waits on a queue of its
    /// own, never on the main actor.
    private struct CoordinatedMove: @unchecked Sendable {
        // MARK: - Variables

        /// The coordinator, kept until it hands the write over.
        let coordinator = NSFileCoordinator()
        /// The write it coordinates, whose `url` is where the file goes.
        let intent: NSFileAccessIntent

        // MARK: - Initializers

        init(to destinationURL: URL) {
            intent = .writingIntent(with: destinationURL, options: .forReplacing)
        }

        // MARK: - Actions - Moving

        /// Moves the file at `stagingURL` in once the coordinator allows it,
        /// at the place the coordinator gives, and returns that place.
        func run(from stagingURL: URL) async throws -> URL {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                coordinator.coordinate(with: [intent], queue: queue) { error in
                    if let error { return continuation.resume(throwing: error) }
                    let placedURL = intent.url
                    do {
                        try FileManager.default.moveItem(at: stagingURL, to: placedURL)
                        continuation.resume(returning: placedURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
