import Foundation
import Observation

struct BrowserSitePermissionChange {
    var spaceID: SpaceID?
    var origin: BrowserSiteOrigin?
    var permission: BrowserSitePermission?
    var detail: String?
    var revokesAuthorization: Bool

    func affects(_ permission: BrowserSitePermission, origin: BrowserSiteOrigin, in spaceID: SpaceID) -> Bool {
        (self.spaceID == nil || self.spaceID == spaceID)
            && (self.origin == nil || self.origin == origin)
            && (self.permission == nil || self.permission == permission)
            && detail == nil
    }
}

@MainActor
protocol BrowserSitePermissionObserver: AnyObject {
    func sitePermissionsDidChange(_ change: BrowserSitePermissionChange)
}

/// Thin native port of the core's per-Space site permission ledger.
///
/// The core owns every rule: which choice answers a request (the narrowest
/// saved choice, then the site-wide rule, with session choices first), the
/// combined camera and microphone rule, listing order, which choices are
/// saved, and the locked-Space gate. This port supplies each Space's lock
/// state, stores the saved document the core returns without reading it, and
/// tells observers what changed. An unanswered question is Ask and an
/// unanswered write records nothing.
@Observable
@MainActor
final class BrowserSitePermissionCenter {
    // MARK: - Types

    private struct Observer {
        weak var value: (any BrowserSitePermissionObserver)?
    }

    /// `load`: the saved document, or null when nothing was saved.
    private struct Load: Encodable {
        @BrowserCoreNullable var document: String?
    }

    /// `decision`.
    private struct Decision: Encodable {
        let spaceID: String
        let origin: BrowserSiteOrigin
        let permission: BrowserSitePermission
        @BrowserCoreNullable var detail: String?
        let locked: Bool
    }

    /// `media_decision`.
    private struct MediaDecision: Encodable {
        let spaceID: String
        let origin: BrowserSiteOrigin
        let media: BrowserMediaPermission
        let locked: Bool
    }

    /// `records`.
    private struct Records: Encodable {
        let spaceID: String
        let locked: Bool
    }

    /// `set`.
    private struct SetDecision: Encodable {
        let spaceID: String
        let origin: BrowserSiteOrigin
        let permission: BrowserSitePermission
        @BrowserCoreNullable var detail: String?
        let decision: BrowserSitePermissionDecision
        let recordID: String
        let now: TimeInterval
        let locked: Bool
    }

    /// `reset_record`.
    private struct ResetRecord: Encodable {
        let id: String
    }

    /// `reset_space`.
    private struct ResetSpace: Encodable {
        let spaceID: String
    }

    private struct DecisionAnswer: Decodable {
        let decision: BrowserSitePermissionDecision
    }

    private struct RecordsAnswer: Decodable {
        let records: [BrowserSitePermissionRecord]
    }

    private struct CommandAnswer: Decodable {
        struct Change: Decodable {
            let spaceID: UUID?
            let origin: BrowserSiteOrigin?
            let permission: BrowserSitePermission?
            let detail: String?
            let revokesAuthorization: Bool
        }

        let applied: Bool
        let document: String?
        let changes: [Change]
    }

    // MARK: - Variables

    private(set) var revision: UInt64 = 0

    @ObservationIgnored private let persistence: any BrowserSitePermissionPersisting
    @ObservationIgnored private let core = BrowserCoreSitePermissionLedger()
    @ObservationIgnored private var observers: [Observer] = []
    @ObservationIgnored private var isSpaceLocked: @MainActor (SpaceID) -> Bool = { _ in false }

    // MARK: - Initializers

    init(persistence: any BrowserSitePermissionPersisting) {
        self.persistence = persistence
        let document = persistence.loadDocument().flatMap { String(data: $0, encoding: .utf8) }
        _ = core.apply(.load, Load(document: document))
    }

    // MARK: - Actions - Lock state

    /// Composition supplies the lock state of every Space it owns. Until then
    /// no Space is locked, as in previews and practice pages that own none.
    func attachSpaceLockState(_ isLocked: @escaping @MainActor (SpaceID) -> Bool) {
        isSpaceLocked = isLocked
        revision &+= 1
    }

    // MARK: - Actions - Decisions

    /// The choice that applies to one request. `detail` narrows a capability a
    /// site can ask for more than one way.
    func decision(
        for permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID
    ) -> BrowserSitePermissionDecision {
        _ = revision
        let request = Decision(
            spaceID: spaceID.rawValue.coreIdentifier, origin: origin, permission: permission, detail: detail,
            locked: isSpaceLocked(spaceID))
        return answer(DecisionAnswer.self, .decision, request)?.decision ?? .ask
    }

    /// Combined capture must respect a block on either device.
    func mediaDecision(
        for media: BrowserMediaPermission,
        origin: BrowserSiteOrigin,
        in spaceID: SpaceID
    ) -> BrowserSitePermissionDecision {
        _ = revision
        let request = MediaDecision(
            spaceID: spaceID.rawValue.coreIdentifier, origin: origin, media: media, locked: isSpaceLocked(spaceID))
        return answer(DecisionAnswer.self, .mediaDecision, request)?.decision ?? .ask
    }

    func records(in spaceID: SpaceID) -> [BrowserSitePermissionRecord] {
        _ = revision
        let request = Records(spaceID: spaceID.rawValue.coreIdentifier, locked: isSpaceLocked(spaceID))
        return answer(RecordsAnswer.self, .records, request)?.records ?? []
    }

    // MARK: - Actions - Observers

    /// Authorization withdrawal must be synchronous: observation can coalesce
    /// a reset followed by a new grant, leaving old requests authorized.
    func addObserver(_ observer: any BrowserSitePermissionObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(Observer(value: observer))
    }

    // MARK: - Actions - Changes

    func setDecision(
        _ decision: BrowserSitePermissionDecision,
        for permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        command(
            .set,
            SetDecision(
                spaceID: spaceID.rawValue.coreIdentifier, origin: origin, permission: permission, detail: detail,
                decision: decision, recordID: UUID().coreIdentifier, now: date.timeIntervalSinceReferenceDate,
                locked: isSpaceLocked(spaceID)))
    }

    func reset(recordID: BrowserSitePermissionRecord.ID) {
        command(.resetRecord, ResetRecord(id: recordID.coreIdentifier))
    }

    func reset(spaceID: SpaceID) {
        command(.resetSpace, ResetSpace(spaceID: spaceID.rawValue.coreIdentifier))
    }

    func resetSession() {
        command(.resetSession, BrowserCoreNoArguments())
    }

    private func command<Arguments: Encodable>(
        _ command: BrowserCoreSitePermissionLedger.Command, _ arguments: Arguments
    ) {
        guard let answer = answer(CommandAnswer.self, command, arguments), answer.applied else { return }
        revision &+= 1
        if let document = answer.document {
            persistence.saveDocument(Data(document.utf8))
        }
        observers.removeAll { $0.value == nil }
        let current = observers.compactMap(\.value)
        for change in answer.changes {
            let change = BrowserSitePermissionChange(
                spaceID: change.spaceID.map(SpaceID.init(rawValue:)), origin: change.origin,
                permission: change.permission, detail: change.detail,
                revokesAuthorization: change.revokesAuthorization)
            for observer in current { observer.sitePermissionsDidChange(change) }
        }
    }

    private func answer<Answer: Decodable, Arguments: Encodable>(
        _ type: Answer.Type, _ command: BrowserCoreSitePermissionLedger.Command, _ arguments: Arguments
    ) -> Answer? {
        guard let data = core.apply(command, arguments) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
