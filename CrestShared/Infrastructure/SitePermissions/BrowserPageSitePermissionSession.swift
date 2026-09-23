import Foundation

/// Keeps one open page's engine in step with Crest's per-Space site permission
/// records, whichever engine hosts it.
///
/// The core decides every answer through `BrowserSitePermissionCenter`; this
/// session only carries the answers to the page. A change made anywhere — the
/// page's own prompt, Site Controls, or the Privacy pane — reaches the page at
/// once rather than on its next navigation:
///
/// - An engine that enforces site permissions itself is told the decision for
///   the page's site through `BrowserPageEngine.applySitePermission`.
/// - Camera or microphone capture the page was granted is stopped through
///   `BrowserPageEngine.stopMediaCapture` when that grant is withdrawn.
/// - `siteDecisionDidChange` runs for each affected permission, so bridges Crest
///   runs inside the page can refresh what the document sees.
@MainActor
final class BrowserPageSitePermissionSession: BrowserSitePermissionObserver {
    // MARK: - Types

    private struct MediaGrant: Hashable {
        let permission: BrowserMediaPermission
        let origin: BrowserSiteOrigin
    }

    // MARK: - Variables

    /// The permissions an engine may enforce itself. Crest's per-Space record
    /// decides them and the engine is told the answer.
    static let engineEnforcedPermissions: [BrowserSitePermission] = [.camera, .microphone, .location, .notifications]

    /// The permissions whose changes the page is told about.
    private static let observedPermissions: [BrowserSitePermission] = engineEnforcedPermissions + [.popups]

    /// The URL of the document the page shows, whose site the engine applies
    /// decisions to.
    var siteURL: @MainActor () -> URL? = { nil }

    /// Runs after a change affected one of the observed permissions for the
    /// page's site.
    var siteDecisionDidChange: @MainActor (BrowserSitePermission) -> Void = { _ in }

    private let engine: any BrowserPageEngine
    private let permissionCenter: BrowserSitePermissionCenter
    private let spaceID: SpaceID
    private var mediaGrants: [MediaGrant: BrowserSitePermissionDecision] = [:]

    // MARK: - Initializers

    init(engine: any BrowserPageEngine, permissionCenter: BrowserSitePermissionCenter, spaceID: SpaceID) {
        self.engine = engine
        self.permissionCenter = permissionCenter
        self.spaceID = spaceID
        permissionCenter.addObserver(self)
    }

    // MARK: - Actions - Media capture

    /// Remembers capture the page was allowed, with the decision that allowed
    /// it, so a later withdrawal of that decision ends the capture.
    func recordMediaGrant(_ permission: BrowserMediaPermission, origin: BrowserSiteOrigin) {
        mediaGrants[MediaGrant(permission: permission, origin: origin)] = permissionCenter.mediaDecision(
            for: permission, origin: origin, in: spaceID)
    }

    /// Forgets capture grants; the document that held them is going away.
    func resetMediaGrants() {
        mediaGrants.removeAll()
    }

    private func revokeChangedMediaGrants() {
        for (grant, previous) in mediaGrants {
            let decision = permissionCenter.mediaDecision(for: grant.permission, origin: grant.origin, in: spaceID)
            guard decision != previous else { continue }
            if decision == .grantPersistently || decision == .grantForSession {
                mediaGrants[grant] = decision
                continue
            }
            mediaGrants.removeValue(forKey: grant)
            engine.stopMediaCapture(grant.permission)
        }
    }

    // MARK: - Actions - Engine-enforced permissions

    /// Applies Crest's record for `url`'s site, or the page's current site, to
    /// an engine that enforces site permissions itself.
    func synchronize(for url: URL? = nil) {
        guard let origin = (url ?? siteURL()).flatMap(BrowserSiteOrigin.init(url:)) else { return }
        for permission in Self.engineEnforcedPermissions {
            apply(permission, origin: origin)
        }
    }

    private func apply(_ permission: BrowserSitePermission, origin: BrowserSiteOrigin) {
        var decision = permissionCenter.decision(for: permission, origin: origin, in: spaceID)
        if decision == .ask, permission == .camera || permission == .microphone {
            decision = permissionCenter.decision(for: .cameraAndMicrophone, origin: origin, in: spaceID)
        }
        let allowed: Bool? =
            switch decision {
            case .grantPersistently, .grantForSession: true
            case .denyPersistently, .denyForSession: false
            case .ask: nil
            }
        _ = engine.applySitePermission(permission, allowed: allowed)
    }

    private func affects(
        _ change: BrowserSitePermissionChange,
        _ permission: BrowserSitePermission,
        origin: BrowserSiteOrigin
    ) -> Bool {
        if change.affects(permission, origin: origin, in: spaceID) { return true }
        // The combined capture record answers either device.
        return (permission == .camera || permission == .microphone)
            && change.affects(.cameraAndMicrophone, origin: origin, in: spaceID)
    }

    // MARK: - Actions - Observation

    func sitePermissionsDidChange(_ change: BrowserSitePermissionChange) {
        revokeChangedMediaGrants()
        guard let origin = siteURL().flatMap(BrowserSiteOrigin.init(url:)) else { return }
        for permission in Self.observedPermissions where affects(change, permission, origin: origin) {
            if Self.engineEnforcedPermissions.contains(permission) {
                apply(permission, origin: origin)
            }
            siteDecisionDidChange(permission)
        }
    }
}
