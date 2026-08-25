import Foundation

struct BrowserDownloadLedger {
    private(set) var items: [BrowserDownloadItem] = []
    private var acknowledgedItemIDs: Set<UUID> = []

    @discardableResult
    mutating func begin(
        profileID: UUID,
        filename: String,
        createdAt: Date = Date()
    ) -> UUID {
        let item = BrowserDownloadItem(
            id: UUID(),
            profileID: profileID,
            createdAt: createdAt,
            filename: filename,
            destinationURL: nil,
            progress: 0,
            state: .preparing,
            riskAssessment: nil
        )
        items.insert(item, at: 0)
        return item.id
    }

    func items(for profileID: UUID) -> [BrowserDownloadItem] {
        items.filter { $0.profileID == profileID }
    }

    func unacknowledgedItems(for profileID: UUID) -> [BrowserDownloadItem] {
        items(for: profileID).filter { !acknowledgedItemIDs.contains($0.id) }
    }

    @discardableResult
    mutating func acknowledgeItems(for profileID: UUID) -> Int {
        let newlyAcknowledged = items(for: profileID)
            .filter { !acknowledgedItemIDs.contains($0.id) }
            .map(\.id)
        acknowledgedItemIDs.formUnion(newlyAcknowledged)
        return newlyAcknowledged.count
    }

    mutating func setDestination(_ destination: URL, for itemID: UUID) {
        update(itemID) { item in
            item.filename = destination.lastPathComponent
            item.destinationURL = destination
            item.state = .downloading
        }
    }

    mutating func setProgress(_ progress: Double, for itemID: UUID) {
        update(itemID) {
            $0.progress = max(
                $0.progress,
                BrowserDownloadProgressPolicy.normalized(progress)
            )
        }
    }

    mutating func setTransferUpdate(
        _ update: BrowserDownloadTransferUpdate,
        for itemID: UUID
    ) {
        self.update(itemID) { item in
            item.telemetry = update.telemetry
            item.progress = max(
                item.progress,
                BrowserDownloadProgressPolicy.normalized(update.progress)
            )
        }
    }

    mutating func setRiskAssessment(_ assessment: BrowserDownloadRiskAssessment, for itemID: UUID) {
        update(itemID) { item in
            item.filename = assessment.sanitizedFilename
            item.riskAssessment = assessment
            if assessment.requiresConfirmation {
                item.state = .awaitingApproval
            }
        }
    }

    mutating func markAwaitingApproval(_ itemID: UUID) {
        update(itemID) { $0.state = .awaitingApproval }
    }

    mutating func finish(_ itemID: UUID, finalByteCount: Int64? = nil) {
        update(itemID) { item in
            item.progress = 1
            item.telemetry = item.telemetry.stopped(
                finalByteCount: finalByteCount,
                completed: true
            )
            item.state = .finished
        }
    }

    mutating func fail(_ itemID: UUID, message: String) {
        update(itemID) {
            $0.telemetry = $0.telemetry.stopped()
            $0.state = .failed(message)
        }
    }

    mutating func cancel(_ itemID: UUID, message: String) {
        update(itemID) {
            $0.telemetry = $0.telemetry.stopped()
            $0.state = .canceled(message)
        }
    }

    mutating func blockAutomaticDownload(_ itemID: UUID) {
        update(itemID) {
            $0.telemetry = $0.telemetry.stopped()
            $0.state = .blockedAutomaticDownload
        }
    }

    mutating func restart(_ itemID: UUID) {
        update(itemID) { item in
            item.destinationURL = nil
            item.progress = 0
            item.telemetry = .empty
            item.state = .preparing
            item.riskAssessment = nil
        }
        acknowledgedItemIDs.remove(itemID)
    }

    mutating func remove(_ itemID: UUID) {
        items.removeAll { $0.id == itemID }
        acknowledgedItemIDs.remove(itemID)
    }

    mutating func removeAll(for profileID: UUID) {
        let removedItemIDs = Set(items(for: profileID).map(\.id))
        items.removeAll { $0.profileID == profileID }
        acknowledgedItemIDs.subtract(removedItemIDs)
    }

    @discardableResult
    mutating func removeExpiredRecords(
        retentionByProfileID: [UUID: BrowserDataRetentionDuration],
        now: Date = .now
    ) -> Set<UUID> {
        let removedItemIDs = Set(
            items.compactMap { item -> UUID? in
                guard Self.isRetainedRecord(item.state),
                    let lifetime = retentionByProfileID[item.profileID]?.lifetime,
                    now.timeIntervalSince(item.createdAt) > lifetime
                else {
                    return nil
                }
                return item.id
            })
        guard !removedItemIDs.isEmpty else { return [] }
        items.removeAll { removedItemIDs.contains($0.id) }
        acknowledgedItemIDs.subtract(removedItemIDs)
        return removedItemIDs
    }

    private mutating func update(
        _ itemID: UUID,
        mutation: (inout BrowserDownloadItem) -> Void
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        mutation(&items[index])
    }

    private static func isRetainedRecord(_ state: BrowserDownloadItemState) -> Bool {
        switch state {
        case .finished, .blockedAutomaticDownload, .canceled, .failed:
            true
        case .preparing, .awaitingApproval, .downloading:
            false
        }
    }
}

extension BrowserDownloadLedger {
    static func showcase(profileID: UUID) -> Self {
        var ledger = Self()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Crest Showcase Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let finishedID = ledger.begin(
            profileID: profileID,
            filename: "Crest Verification Notes.txt",
            createdAt: .now.addingTimeInterval(-90)
        )
        let finishedURL = directory.appendingPathComponent(
            "Crest Verification Notes.txt"
        )
        try? Data("Crest download verification fixture\n".utf8).write(
            to: finishedURL,
            options: .atomic
        )
        ledger.setDestination(finishedURL, for: finishedID)
        ledger.finish(
            finishedID,
            finalByteCount: Int64(
                (try? finishedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    ?? 0
            )
        )

        let activeID = ledger.begin(
            profileID: profileID,
            filename: "Crest Design Review.pdf",
            createdAt: .now
        )
        ledger.setDestination(
            directory.appendingPathComponent("Crest Design Review.pdf"),
            for: activeID
        )
        ledger.setProgress(0.64, for: activeID)
        ledger.setTransferUpdate(
            BrowserDownloadTransferUpdate(
                telemetry: BrowserDownloadTransferTelemetry(
                    bytesReceived: 8_388_608,
                    totalBytes: 13_107_200,
                    bytesPerSecond: 1_572_864,
                    estimatedTimeRemaining: 3,
                    isPaused: false
                ),
                progress: 0.64
            ),
            for: activeID
        )
        return ledger
    }
}
