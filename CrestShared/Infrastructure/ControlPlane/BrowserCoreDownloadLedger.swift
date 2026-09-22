import CrestCoreABI
import Foundation
import Observation
import os

/// Thin native port of the core's process-local download ledger.
///
/// The core owns the record state machine, newest-first ordering,
/// acknowledgement and retention expiry. Each command returns a delta that
/// this projection applies in place, so views read `items` without crossing
/// the boundary. Nothing here is persisted or synced.
@MainActor
@Observable
final class BrowserDownloadLedger {
    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CoreDownloads")

    private(set) var items: [BrowserDownloadItem] = []
    private let handle: UInt64

    init() {
        var value: UInt64 = 0
        precondition(crest_downloads_create(&value) == CREST_OK, "Could not initialize the download ledger")
        handle = value
    }

    deinit { crest_downloads_destroy(handle) }

    func items(for profileID: UUID) -> [BrowserDownloadItem] {
        items.filter { $0.profileID == profileID }
    }

    func unacknowledgedItems(for profileID: UUID) -> [BrowserDownloadItem] {
        items.filter { $0.profileID == profileID && !$0.isAcknowledged }
    }

    func item(_ itemID: UUID) -> BrowserDownloadItem? {
        items.first { $0.id == itemID }
    }

    /// A download an engine restored from an earlier run starts acknowledged.
    @discardableResult
    func begin(profileID: UUID, filename: String, createdAt: Date = Date(), isAcknowledged: Bool = false) -> UUID {
        let itemID = UUID()
        apply("begin", ["id": Self.text(itemID), "profileID": Self.text(profileID), "filename": filename,
            "createdAt": createdAt.timeIntervalSinceReferenceDate, "acknowledged": isAcknowledged])
        return itemID
    }

    @discardableResult
    func acknowledgeItems(for profileID: UUID) -> Int {
        apply("acknowledge_profile", ["profileID": Self.text(profileID)])?.changed ?? 0
    }

    func setDestination(_ destination: URL, for itemID: UUID) {
        apply("destination", ["id": Self.text(itemID), "destination": destination.absoluteString,
            "filename": destination.lastPathComponent])
    }

    func setTransferUpdate(_ update: BrowserDownloadTransferUpdate, for itemID: UUID) {
        let telemetry = update.telemetry
        apply("transfer", ["id": Self.text(itemID), "progress": update.progress, "telemetry": [
            "bytesReceived": telemetry.bytesReceived, "totalBytes": telemetry.totalBytes as Any? ?? NSNull(),
            "bytesPerSecond": telemetry.bytesPerSecond as Any? ?? NSNull(),
            "estimatedTimeRemaining": telemetry.estimatedTimeRemaining as Any? ?? NSNull(),
            "isPaused": telemetry.isPaused,
        ] as [String: Any]])
    }

    func setRiskAssessment(_ assessment: BrowserDownloadRiskAssessment, for itemID: UUID) {
        apply("assess_risk", ["id": Self.text(itemID), "assessment": [
            "sanitizedFilename": assessment.sanitizedFilename,
            "reasons": assessment.reasons.map(\.rawValue),
        ] as [String: Any]])
    }

    func markAwaitingApproval(_ itemID: UUID) {
        apply("await_approval", ["id": Self.text(itemID)])
    }

    func finish(_ itemID: UUID, finalByteCount: Int64? = nil) {
        apply("finish", ["id": Self.text(itemID), "finalByteCount": finalByteCount as Any? ?? NSNull()])
    }

    func fail(_ itemID: UUID, message: String) {
        apply("fail", ["id": Self.text(itemID), "message": message])
    }

    func cancel(_ itemID: UUID, message: String) {
        apply("cancel", ["id": Self.text(itemID), "message": message])
    }

    func blockAutomaticDownload(_ itemID: UUID) {
        apply("block", ["id": Self.text(itemID)])
    }

    func restart(_ itemID: UUID) {
        apply("restart", ["id": Self.text(itemID)])
    }

    func remove(_ itemID: UUID) {
        apply("remove", ["id": Self.text(itemID)])
    }

    func removeAll(for profileID: UUID) {
        apply("remove_profile", ["profileID": Self.text(profileID)])
    }

    /// One entry per Space; the core applies the shortest retention among
    /// Spaces sharing a profile. A nil lifetime keeps records forever.
    @discardableResult
    func removeExpiredRecords(retention: [(profileID: UUID, lifetime: TimeInterval?)], now: Date = .now) -> Set<UUID> {
        apply("expire", ["now": now.timeIntervalSinceReferenceDate, "retention": retention.map {
            ["profileID": Self.text($0.profileID), "lifetime": $0.lifetime as Any? ?? NSNull()] as [String: Any]
        }])?.removed ?? []
    }

    @discardableResult
    private func apply(_ command: String, _ arguments: [String: Any]) -> (changed: Int, removed: Set<UUID>)? {
        var request = arguments
        request["version"] = 1
        request["command"] = command
        guard let response = execute(request) else { return nil }
        let removed = Set((response["removed"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        let changed = (response["items"] as? [[String: Any]] ?? []).compactMap { entry -> (Int, BrowserDownloadItem)? in
            guard let index = entry["index"] as? Int, let values = entry["item"] as? [String: Any],
                let item = BrowserDownloadItem(coreValues: values) else { return nil }
            return (index, item)
        }
        guard !removed.isEmpty || !changed.isEmpty else { return (0, []) }
        var projected = items
        if !removed.isEmpty { projected.removeAll { removed.contains($0.id) } }
        for (index, item) in changed {
            if let current = projected.firstIndex(where: { $0.id == item.id }) {
                projected[current] = item
            } else {
                projected.insert(item, at: min(max(index, 0), projected.count))
            }
        }
        items = projected
        return (changed.count, removed)
    }

    private func execute(_ request: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        var length = 0
        let applied = data.withUnsafeBytes {
            crest_downloads_apply(handle, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &length)
        }
        guard applied == CREST_OK, length > 0 else {
            Self.logger.error("Core download ledger rejected \(request["command"] as? String ?? "unknown", privacy: .public): \(applied)")
            return nil
        }
        var output = Data(count: length)
        let capacity = length
        let read = output.withUnsafeMutableBytes {
            crest_downloads_read(handle, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        }
        guard read == CREST_OK else {
            Self.logger.error("Core download ledger output failed: \(read)")
            return nil
        }
        return try? JSONSerialization.jsonObject(with: output) as? [String: Any]
    }

    private static func text(_ id: UUID) -> String { id.uuidString.lowercased() }
}

/// Per-transfer holder for the core progress policy's state. Rate smoothing,
/// monotonic bytes, total validation and the estimate all live in the core.
struct BrowserDownloadTransferEstimator {
    private var state: [String: Any]?

    /// Nil when the core cannot answer; the caller keeps the last reading.
    mutating func sample(
        completedUnitCount: Int64,
        totalUnitCount: Int64,
        fractionCompleted: Double,
        isPaused: Bool,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BrowserDownloadTransferUpdate? {
        guard let reading = BrowserCorePolicy.downloadProgress(estimator: state,
            completedUnitCount: completedUnitCount, totalUnitCount: totalUnitCount,
            fractionCompleted: fractionCompleted, isPaused: isPaused, uptime: uptime) else { return nil }
        state = reading.estimator
        return reading.update
    }
}

extension BrowserDownloadItem {
    /// Decodes one record of the core ledger's projection.
    fileprivate init?(coreValues values: [String: Any]) {
        guard let id = (values["id"] as? String).flatMap(UUID.init(uuidString:)),
            let profileID = (values["profileID"] as? String).flatMap(UUID.init(uuidString:)),
            let createdAt = (values["createdAt"] as? NSNumber)?.doubleValue,
            let filename = values["filename"] as? String,
            let progress = (values["progress"] as? NSNumber)?.doubleValue,
            let telemetry = (values["telemetry"] as? [String: Any]).flatMap(BrowserDownloadTransferTelemetry.init(coreValues:)),
            let state = BrowserDownloadItemState(coreState: values["state"] as? String, message: values["message"] as? String)
        else { return nil }
        let risk = (values["risk"] as? [String: Any]).flatMap { risk -> BrowserDownloadRiskAssessment? in
            guard let sanitizedFilename = risk["sanitizedFilename"] as? String,
                let reasons = risk["reasons"] as? [String] else { return nil }
            return BrowserDownloadRiskAssessment(sanitizedFilename: sanitizedFilename,
                reasons: reasons.compactMap(BrowserDownloadRiskReason.init(rawValue:)))
        }
        self.init(id: id, profileID: profileID, createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            filename: filename, destinationURL: (values["destination"] as? String).flatMap(URL.init(string:)),
            progress: progress, telemetry: telemetry, state: state, riskAssessment: risk,
            isAcknowledged: values["acknowledged"] as? Bool ?? false)
    }
}

extension BrowserDownloadTransferTelemetry {
    init?(coreValues values: [String: Any]) {
        guard let bytesReceived = (values["bytesReceived"] as? NSNumber)?.int64Value,
            let isPaused = values["isPaused"] as? Bool else { return nil }
        self.init(bytesReceived: bytesReceived,
            totalBytes: (values["totalBytes"] as? NSNumber)?.int64Value,
            bytesPerSecond: (values["bytesPerSecond"] as? NSNumber)?.doubleValue,
            estimatedTimeRemaining: (values["estimatedTimeRemaining"] as? NSNumber)?.doubleValue,
            isPaused: isPaused)
    }
}

extension BrowserDownloadItemState {
    fileprivate init?(coreState: String?, message: String?) {
        switch coreState {
        case "preparing": self = .preparing
        case "awaitingApproval": self = .awaitingApproval
        case "downloading": self = .downloading
        case "finished": self = .finished
        case "blockedAutomaticDownload": self = .blockedAutomaticDownload
        case "canceled": self = .canceled(message ?? "")
        case "failed": self = .failed(message ?? "")
        default: return nil
        }
    }
}

extension BrowserDownloadLedger {
    static func showcase(profileID: UUID) -> BrowserDownloadLedger {
        let ledger = BrowserDownloadLedger()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Crest Showcase Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let finishedID = ledger.begin(profileID: profileID, filename: "Crest Verification Notes.txt",
            createdAt: .now.addingTimeInterval(-90))
        let finishedURL = directory.appendingPathComponent("Crest Verification Notes.txt")
        try? Data("Crest download verification fixture\n".utf8).write(to: finishedURL, options: .atomic)
        ledger.setDestination(finishedURL, for: finishedID)
        ledger.finish(finishedID, finalByteCount: Int64(
            (try? finishedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))

        let activeID = ledger.begin(profileID: profileID, filename: "Crest Design Review.pdf", createdAt: .now)
        ledger.setDestination(directory.appendingPathComponent("Crest Design Review.pdf"), for: activeID)
        ledger.setTransferUpdate(
            BrowserDownloadTransferUpdate(
                telemetry: BrowserDownloadTransferTelemetry(bytesReceived: 8_388_608, totalBytes: 13_107_200,
                    bytesPerSecond: 1_572_864, estimatedTimeRemaining: 3, isPaused: false),
                progress: 0.64),
            for: activeID)
        return ledger
    }
}
