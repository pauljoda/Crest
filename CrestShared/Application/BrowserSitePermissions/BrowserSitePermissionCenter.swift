import Foundation
import os

struct BrowserSitePermissionChange {
    var spaceID: SpaceID?
    var origin: BrowserSiteOrigin?
    var permission: SitePermission?
    var detail: String?
    var revokesAuthorization: Bool

    func affects(_ permission: SitePermission, origin: BrowserSiteOrigin, in spaceID: SpaceID) -> Bool {
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

/// The platform's side of the core's site permission choices.
///
/// The core owns every rule and every choice: which choice answers a request
/// (the narrowest saved choice, then the site-wide rule, with session choices
/// first), the combined camera and microphone rule, the locked-Space gate,
/// listing order, and which choices the device store keeps. This center asks
/// the core its questions, sends the person's answers as intents, reads each
/// Space's kept choices from the read model, and tells the pages observing it
/// what each change covered. An answer a rule refuses records nothing.
@MainActor
final class BrowserSitePermissionCenter {
    // MARK: - Static Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "SitePermissions")

    // MARK: - Types

    private struct Observer {
        weak var value: (any BrowserSitePermissionObserver)?
    }

    // MARK: - Variables

    private let core: CrestCore
    private var observers: [Observer] = []

    // MARK: - Initializers

    /// A center over `core`, whose changes it passes to its observers.
    init(core: CrestCore) {
        self.core = core
        core.followSitePermissions(self) { [weak self] change in self?.changed(change) }
    }

    /// A center over a memory-only core of its own, as previews, practice
    /// pages and tests use, which keeps nothing.
    convenience init() {
        self.init(core: CrestCore())
    }

    // MARK: - Actions - Adoption

    /// Carries the document an installed release kept under
    /// `crest.site-permissions.v1` into the core's device store, once, and
    /// seeds the read model with every Space's kept choices.
    func adoptLegacyRecords(_ document: Data?) {
        do {
            try core.send(AdoptSitePermissions(records: document))
        } catch {
            Self.logger.error(
                "The core could not adopt the saved site permissions: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Actions - Decisions

    /// The choice that applies to one request. `detail` narrows a capability a
    /// site can ask for more than one way.
    func decision(
        for permission: SitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID
    ) -> SitePermissionDecision {
        _ = core.state.sitePermissionRevision
        let question = SiteDecision(
            spaceID: spaceID, origin: origin.core, permission: permission, detail: detail)
        return (try? core.query(question))?.decision ?? .ask
    }

    /// Combined capture must respect a block on either device.
    func mediaDecision(
        for media: SitePermission,
        origin: BrowserSiteOrigin,
        in spaceID: SpaceID
    ) -> SitePermissionDecision {
        _ = core.state.sitePermissionRevision
        let question = CaptureDecision(spaceID: spaceID, origin: origin.core, media: media)
        return (try? core.query(question))?.decision ?? .ask
    }

    /// The choices a Space keeps, in the order the settings list them.
    func records(in spaceID: SpaceID) -> [SitePermissionRecordState] {
        core.state.sitePermissions[spaceID] ?? []
    }

    // MARK: - Actions - Observers

    /// Authorization withdrawal must be synchronous: observation can coalesce
    /// a reset followed by a new grant, leaving old requests authorized.
    func addObserver(_ observer: any BrowserSitePermissionObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(Observer(value: observer))
    }

    /// Tells each observer what one applied change covered.
    private func changed(_ change: SitePermissionsChanged) {
        observers.removeAll { $0.value == nil }
        let current = observers.compactMap(\.value)
        for scope in change.touched {
            let touched = BrowserSitePermissionChange(
                spaceID: change.spaceID, origin: scope.origin.map(BrowserSiteOrigin.init),
                permission: scope.permission, detail: scope.detail, revokesAuthorization: scope.revokesAuthorization)
            for observer in current { observer.sitePermissionsDidChange(touched) }
        }
    }

    // MARK: - Actions - Changes

    func setDecision(
        _ decision: SitePermissionDecision,
        for permission: SitePermission,
        origin: BrowserSiteOrigin,
        detail: String? = nil,
        in spaceID: SpaceID
    ) {
        send(
            DecideSitePermission(
                spaceID: spaceID, origin: origin.core, permission: permission, detail: detail,
                decision: decision))
    }

    func reset(recordID: UUID) {
        send(ResetSitePermission(recordID: recordID))
    }

    func reset(spaceID: SpaceID) {
        send(ResetSpacePermissions(spaceID: spaceID))
    }

    private func send(_ intent: some SitePermissionIntent) {
        do {
            try core.send(intent)
        } catch {
            Self.logger.notice(
                "The core refused \(String(describing: type(of: intent)), privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
