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
    private struct Observer {
        weak var value: (any BrowserSitePermissionObserver)?
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

    private(set) var revision: UInt64 = 0

    @ObservationIgnored private let persistence: any BrowserSitePermissionPersisting
    @ObservationIgnored private let core = BrowserCoreSitePermissionLedger()
    @ObservationIgnored private var observers: [Observer] = []
    @ObservationIgnored private var isSpaceLocked: @MainActor (SpaceID) -> Bool = { _ in false }

    init(persistence: any BrowserSitePermissionPersisting) {
        self.persistence = persistence
        let document = persistence.loadDocument().flatMap { String(data: $0, encoding: .utf8) }
        _ = core.apply("load", ["document": document as Any? ?? NSNull()])
    }

    /// Composition supplies the lock state of every Space it owns. Until then
    /// no Space is locked, as in previews and practice pages that own none.
    func attachSpaceLockState(_ isLocked: @escaping @MainActor (SpaceID) -> Bool) {
        isSpaceLocked = isLocked
        revision &+= 1
    }

    /// The choice that applies to one request. `detail` narrows a capability a
    /// site can ask for more than one way.
    func decision(
        for permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID
    ) -> BrowserSitePermissionDecision {
        _ = revision
        return answer(DecisionAnswer.self, "decision", [
            "spaceID": Self.text(spaceID), "origin": origin.coreValue, "permission": permission.rawValue,
            "detail": detail as Any? ?? NSNull(), "locked": isSpaceLocked(spaceID),
        ])?.decision ?? .ask
    }

    /// Combined capture must respect a block on either device.
    func mediaDecision(
        for media: BrowserMediaPermission,
        origin: BrowserSiteOrigin,
        in spaceID: SpaceID
    ) -> BrowserSitePermissionDecision {
        _ = revision
        return answer(DecisionAnswer.self, "media_decision", [
            "spaceID": Self.text(spaceID), "origin": origin.coreValue, "media": media.rawValue,
            "locked": isSpaceLocked(spaceID),
        ])?.decision ?? .ask
    }

    func records(in spaceID: SpaceID) -> [BrowserSitePermissionRecord] {
        _ = revision
        return answer(RecordsAnswer.self, "records", [
            "spaceID": Self.text(spaceID), "locked": isSpaceLocked(spaceID),
        ])?.records ?? []
    }

    /// Authorization withdrawal must be synchronous: observation can coalesce
    /// a reset followed by a new grant, leaving old requests authorized.
    func addObserver(_ observer: any BrowserSitePermissionObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(Observer(value: observer))
    }

    func setDecision(
        _ decision: BrowserSitePermissionDecision,
        for permission: BrowserSitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        command("set", [
            "spaceID": Self.text(spaceID), "origin": origin.coreValue, "permission": permission.rawValue,
            "detail": detail as Any? ?? NSNull(), "decision": decision.rawValue,
            "recordID": UUID().uuidString.lowercased(), "now": date.timeIntervalSinceReferenceDate,
            "locked": isSpaceLocked(spaceID),
        ])
    }

    func reset(recordID: BrowserSitePermissionRecord.ID) {
        command("reset_record", ["id": recordID.uuidString.lowercased()])
    }

    func reset(spaceID: SpaceID) {
        command("reset_space", ["spaceID": Self.text(spaceID)])
    }

    func resetSession() {
        command("reset_session", [:])
    }

    private func command(_ name: String, _ arguments: [String: Any]) {
        guard let answer = answer(CommandAnswer.self, name, arguments), answer.applied else { return }
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

    private func answer<Answer: Decodable>(_ type: Answer.Type, _ command: String, _ arguments: [String: Any]) -> Answer? {
        guard let data = core.apply(command, arguments) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func text(_ spaceID: SpaceID) -> String { spaceID.rawValue.uuidString.lowercased() }
}
