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

    mutating func acknowledgeItems(for profileID: UUID) {
        acknowledgedItemIDs.formUnion(items(for: profileID).map(\.id))
    }

    mutating func setDestination(_ destination: URL, for itemID: UUID) {
        update(itemID) { item in
            item.filename = destination.lastPathComponent
            item.destinationURL = destination
            item.state = .downloading
        }
    }

    mutating func setProgress(_ progress: Double, for itemID: UUID) {
        update(itemID) { $0.progress = BrowserDownloadProgressPolicy.normalized(progress) }
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

    mutating func finish(_ itemID: UUID) {
        update(itemID) { item in
            item.progress = 1
            item.state = .finished
        }
    }

    mutating func fail(_ itemID: UUID, message: String) {
        update(itemID) { $0.state = .failed(message) }
    }

    mutating func cancel(_ itemID: UUID, message: String) {
        update(itemID) { $0.state = .canceled(message) }
    }

    mutating func blockAutomaticDownload(_ itemID: UUID) {
        update(itemID) { $0.state = .blockedAutomaticDownload }
    }

    mutating func restart(_ itemID: UUID) {
        update(itemID) { item in
            item.destinationURL = nil
            item.progress = 0
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
