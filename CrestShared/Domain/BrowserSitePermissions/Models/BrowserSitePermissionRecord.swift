import Foundation

struct BrowserSitePermissionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let spaceID: SpaceID
    let origin: BrowserSiteOrigin
    let permission: SitePermission
    /// Narrows a capability that a site can ask for more than one way, such as
    /// the URL scheme behind one external-app hand-off. Optional so that every
    /// record written before capabilities gained a second dimension — and every
    /// site-wide rule written after — keeps decoding and keeps applying.
    let detail: String?
    var decision: SitePermissionDecision
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        spaceID: SpaceID,
        origin: BrowserSiteOrigin,
        permission: SitePermission,
        detail: String? = nil,
        decision: SitePermissionDecision,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.spaceID = spaceID
        self.origin = origin
        self.permission = permission
        self.detail = detail
        self.decision = decision
        self.modifiedAt = modifiedAt
    }
}
