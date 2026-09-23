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
    // MARK: - Types

    /// One ledger command. Raw values are the core's spellings in
    /// `DownloadCommand.cs`.
    enum Command: String, Encodable, Sendable {
        case acknowledgeProfile = "acknowledge_profile"
        case assessRisk = "assess_risk"
        case awaitApproval = "await_approval"
        case begin
        case block
        case cancel
        case destination
        case expire
        case fail
        case finish
        case remove
        case removeProfile = "remove_profile"
        case restart
        case transfer
    }

    /// Every ledger request: the version and command, then the command's own
    /// members at the same level.
    private struct Request<Arguments: Encodable>: Encodable {
        private enum CodingKeys: String, CodingKey {
            case version
            case command
        }

        let command: Command
        let arguments: Arguments

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(1, forKey: .version)
            try container.encode(command, forKey: .command)
            try arguments.encode(to: encoder)
        }
    }

    private struct Item: Encodable {
        let id: String
    }

    private struct Profile: Encodable {
        let profileID: String
    }

    private struct Begin: Encodable {
        let id: String
        let profileID: String
        let filename: String
        let createdAt: TimeInterval
        let acknowledged: Bool
    }

    private struct Destination: Encodable {
        let id: String
        let destination: String
        let filename: String
    }

    private struct Transfer: Encodable {
        let id: String
        let progress: Double
        let telemetry: BrowserDownloadTransferTelemetry
    }

    private struct RiskAssessment: Encodable {
        struct Assessment: Encodable {
            let sanitizedFilename: String
            let reasons: [BrowserDownloadRiskReason]
        }

        let id: String
        let assessment: Assessment
    }

    private struct Finish: Encodable {
        let id: String
        @BrowserCoreNullable var finalByteCount: Int64?
    }

    private struct Message: Encodable {
        let id: String
        let message: String
    }

    private struct Expire: Encodable {
        struct Retention: Encodable {
            let profileID: String
            @BrowserCoreNullable var lifetime: TimeInterval?
        }

        let now: TimeInterval
        let retention: [Retention]
    }

    /// The delta one command answers: records it changed, each with its place
    /// in the newest-first list, and records it removed.
    private struct Delta: Decodable {
        struct Change: Decodable {
            let index: Int
            let item: BrowserDownloadItem
        }

        @BrowserCoreOptional var removed: BrowserCoreKnownValues<UUID>?
        @BrowserCoreOptional var items: BrowserCoreKnownValues<Change>?
    }

    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CoreDownloads")

    private(set) var items: [BrowserDownloadItem] = []
    private let handle: UInt64

    // MARK: - Initializers

    init() {
        var value: UInt64 = 0
        precondition(crest_downloads_create(&value) == CREST_OK, "Could not initialize the download ledger")
        handle = value
    }

    deinit { crest_downloads_destroy(handle) }

    // MARK: - Actions - Reading

    func items(for profileID: UUID) -> [BrowserDownloadItem] {
        items.filter { $0.profileID == profileID }
    }

    func unacknowledgedItems(for profileID: UUID) -> [BrowserDownloadItem] {
        items.filter { $0.profileID == profileID && !$0.isAcknowledged }
    }

    func item(_ itemID: UUID) -> BrowserDownloadItem? {
        items.first { $0.id == itemID }
    }

    // MARK: - Actions - Commands

    /// A download an engine restored from an earlier run starts acknowledged.
    @discardableResult
    func begin(profileID: UUID, filename: String, createdAt: Date = Date(), isAcknowledged: Bool = false) -> UUID {
        let itemID = UUID()
        apply(
            .begin,
            Begin(
                id: itemID.coreIdentifier, profileID: profileID.coreIdentifier, filename: filename,
                createdAt: createdAt.timeIntervalSinceReferenceDate, acknowledged: isAcknowledged))
        return itemID
    }

    @discardableResult
    func acknowledgeItems(for profileID: UUID) -> Int {
        apply(.acknowledgeProfile, Profile(profileID: profileID.coreIdentifier))?.changed ?? 0
    }

    func setDestination(_ destination: URL, for itemID: UUID) {
        apply(
            .destination,
            Destination(
                id: itemID.coreIdentifier, destination: destination.absoluteString,
                filename: destination.lastPathComponent))
    }

    func setTransferUpdate(_ update: BrowserDownloadTransferUpdate, for itemID: UUID) {
        apply(.transfer, Transfer(id: itemID.coreIdentifier, progress: update.progress, telemetry: update.telemetry))
    }

    func setRiskAssessment(_ assessment: BrowserDownloadRiskAssessment, for itemID: UUID) {
        apply(
            .assessRisk,
            RiskAssessment(
                id: itemID.coreIdentifier,
                assessment: RiskAssessment.Assessment(
                    sanitizedFilename: assessment.sanitizedFilename, reasons: assessment.reasons)))
    }

    func markAwaitingApproval(_ itemID: UUID) {
        apply(.awaitApproval, Item(id: itemID.coreIdentifier))
    }

    func finish(_ itemID: UUID, finalByteCount: Int64? = nil) {
        apply(.finish, Finish(id: itemID.coreIdentifier, finalByteCount: finalByteCount))
    }

    func fail(_ itemID: UUID, message: String) {
        apply(.fail, Message(id: itemID.coreIdentifier, message: message))
    }

    func cancel(_ itemID: UUID, message: String) {
        apply(.cancel, Message(id: itemID.coreIdentifier, message: message))
    }

    func blockAutomaticDownload(_ itemID: UUID) {
        apply(.block, Item(id: itemID.coreIdentifier))
    }

    func restart(_ itemID: UUID) {
        apply(.restart, Item(id: itemID.coreIdentifier))
    }

    func remove(_ itemID: UUID) {
        apply(.remove, Item(id: itemID.coreIdentifier))
    }

    func removeAll(for profileID: UUID) {
        apply(.removeProfile, Profile(profileID: profileID.coreIdentifier))
    }

    /// One entry per Space; the core applies the shortest retention among
    /// Spaces sharing a profile. A nil lifetime keeps records forever.
    @discardableResult
    func removeExpiredRecords(retention: [(profileID: UUID, lifetime: TimeInterval?)], now: Date = .now) -> Set<UUID> {
        apply(
            .expire,
            Expire(
                now: now.timeIntervalSinceReferenceDate,
                retention: retention.map {
                    Expire.Retention(profileID: $0.profileID.coreIdentifier, lifetime: $0.lifetime)
                }))?.removed ?? []
    }

    @discardableResult
    private func apply<Arguments: Encodable>(_ command: Command, _ arguments: Arguments)
        -> (changed: Int, removed: Set<UUID>)?
    {
        guard let delta = execute(command, arguments) else { return nil }
        let removed = Set(delta.removed?.values ?? [])
        let changed = delta.items?.values ?? []
        guard !removed.isEmpty || !changed.isEmpty else { return (0, []) }
        var projected = items
        if !removed.isEmpty { projected.removeAll { removed.contains($0.id) } }
        for change in changed {
            if let current = projected.firstIndex(where: { $0.id == change.item.id }) {
                projected[current] = change.item
            } else {
                projected.insert(change.item, at: min(max(change.index, 0), projected.count))
            }
        }
        items = projected
        return (changed.count, removed)
    }

    private func execute<Arguments: Encodable>(_ command: Command, _ arguments: Arguments) -> Delta? {
        guard let data = try? JSONEncoder().encode(Request(command: command, arguments: arguments)) else {
            return nil
        }
        var length = 0
        let applied = data.withUnsafeBytes {
            crest_downloads_apply(handle, $0.bindMemory(to: UInt8.self).baseAddress, data.count, &length)
        }
        guard applied == CREST_OK, length > 0 else {
            Self.logger.error("Core download ledger rejected \(command.rawValue, privacy: .public): \(applied)")
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
        return try? JSONDecoder().decode(Delta.self, from: output)
    }
}

/// Per-transfer holder for the core progress policy's state. Rate smoothing,
/// monotonic bytes, total validation and the estimate all live in the core.
struct BrowserDownloadTransferEstimator {
    private var state: BrowserCoreOpaqueValue?

    /// Nil when the core cannot answer; the caller keeps the last reading.
    mutating func sample(
        completedUnitCount: Int64,
        totalUnitCount: Int64,
        fractionCompleted: Double,
        isPaused: Bool,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BrowserDownloadTransferUpdate? {
        guard
            let reading = BrowserCorePolicy.downloadProgress(
                estimator: state,
                completedUnitCount: completedUnitCount, totalUnitCount: totalUnitCount,
                fractionCompleted: fractionCompleted, isPaused: isPaused, uptime: uptime)
        else { return nil }
        state = reading.estimator
        return reading.update
    }
}

/// One record of the core ledger's projection, in the core's spelling.
extension BrowserDownloadItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case profileID
        case createdAt
        case filename
        case destination
        case progress
        case telemetry
        case state
        case message
        case risk
        case acknowledged
    }

    /// Raw values are the core's download state spellings.
    private enum CoreState: String, Decodable {
        case preparing
        case awaitingApproval
        case downloading
        case finished
        case blockedAutomaticDownload
        case canceled
        case failed
    }

    /// A risk assessment keeps the reasons this build understands.
    private struct CoreRisk: Decodable {
        let sanitizedFilename: String
        let reasons: BrowserCoreKnownValues<BrowserDownloadRiskReason>
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let message = try container.decode(BrowserCoreOptional<String>.self, forKey: .message).wrappedValue
        let state: BrowserDownloadItemState =
            switch try container.decode(CoreState.self, forKey: .state) {
            case .preparing: .preparing
            case .awaitingApproval: .awaitingApproval
            case .downloading: .downloading
            case .finished: .finished
            case .blockedAutomaticDownload: .blockedAutomaticDownload
            case .canceled: .canceled(message ?? "")
            case .failed: .failed(message ?? "")
            }
        let risk = try container.decode(BrowserCoreOptional<CoreRisk>.self, forKey: .risk).wrappedValue
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            profileID: try container.decode(UUID.self, forKey: .profileID),
            createdAt: Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .createdAt)),
            filename: try container.decode(String.self, forKey: .filename),
            destinationURL: try container.decode(BrowserCoreOptional<String>.self, forKey: .destination)
                .wrappedValue.flatMap(URL.init(string:)),
            progress: try container.decode(Double.self, forKey: .progress),
            telemetry: try container.decode(BrowserDownloadTransferTelemetry.self, forKey: .telemetry),
            state: state,
            riskAssessment: risk.map {
                BrowserDownloadRiskAssessment(sanitizedFilename: $0.sanitizedFilename, reasons: $0.reasons.values)
            },
            isAcknowledged: try container.decode(BrowserCoreOptional<Bool>.self, forKey: .acknowledged)
                .wrappedValue ?? false)
    }
}

/// Transfer telemetry as the ledger and the progress policy spell it. Unknown
/// quantities cross as `null`.
extension BrowserDownloadTransferTelemetry: Codable {
    private enum CodingKeys: String, CodingKey {
        case bytesReceived
        case totalBytes
        case bytesPerSecond
        case estimatedTimeRemaining
        case isPaused
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bytesReceived: try container.decode(Int64.self, forKey: .bytesReceived),
            totalBytes: try container.decode(BrowserCoreOptional<Int64>.self, forKey: .totalBytes).wrappedValue,
            bytesPerSecond: try container.decode(BrowserCoreOptional<Double>.self, forKey: .bytesPerSecond)
                .wrappedValue,
            estimatedTimeRemaining: try container.decode(
                BrowserCoreOptional<Double>.self, forKey: .estimatedTimeRemaining
            ).wrappedValue,
            isPaused: try container.decode(Bool.self, forKey: .isPaused))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bytesReceived, forKey: .bytesReceived)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(bytesPerSecond, forKey: .bytesPerSecond)
        try container.encode(estimatedTimeRemaining, forKey: .estimatedTimeRemaining)
        try container.encode(isPaused, forKey: .isPaused)
    }
}

extension BrowserDownloadLedger {
    static func showcase(profileID: UUID) -> BrowserDownloadLedger {
        let ledger = BrowserDownloadLedger()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Crest Showcase Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let finishedID = ledger.begin(
            profileID: profileID, filename: "Crest Verification Notes.txt",
            createdAt: .now.addingTimeInterval(-90))
        let finishedURL = directory.appendingPathComponent("Crest Verification Notes.txt")
        try? Data("Crest download verification fixture\n".utf8).write(to: finishedURL, options: .atomic)
        ledger.setDestination(finishedURL, for: finishedID)
        ledger.finish(
            finishedID,
            finalByteCount: Int64(
                (try? finishedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))

        let activeID = ledger.begin(profileID: profileID, filename: "Crest Design Review.pdf", createdAt: .now)
        ledger.setDestination(directory.appendingPathComponent("Crest Design Review.pdf"), for: activeID)
        ledger.setTransferUpdate(
            BrowserDownloadTransferUpdate(
                telemetry: BrowserDownloadTransferTelemetry(
                    bytesReceived: 8_388_608, totalBytes: 13_107_200,
                    bytesPerSecond: 1_572_864, estimatedTimeRemaining: 3, isPaused: false),
                progress: 0.64),
            for: activeID)
        return ledger
    }
}
