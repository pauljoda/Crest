import Foundation

struct ArchivedTab: Codable, Equatable, Identifiable, Sendable {
    var id: TabID { tab.id }
    var tab: BrowserTab
    var archivedAt: Date
    var reason: ArchiveReason

    init(tab: BrowserTab, archivedAt: Date, reason: ArchiveReason) {
        self.tab = tab
        self.archivedAt = archivedAt
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case tab
        case archivedAt
        case reason
        case deletionOrigin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tab = try container.decode(BrowserTab.self, forKey: .tab)
        archivedAt = try container.decode(Date.self, forKey: .archivedAt)
        // A reason this build does not know reads as a close.
        let storedReason =
            (try? container.decodeIfPresent(String.self, forKey: .reason)).flatMap(ArchiveReason.named) ?? .closed
        let deletionOrigin = try container.decodeIfPresent(String.self, forKey: .deletionOrigin)
        reason =
            ArchiveReason.all.first { $0.deletionOrigin != nil && $0.deletionOrigin == deletionOrigin }
            ?? storedReason
    }

    /// Keep the required `reason` term readable by builds shipped before
    /// deletion audits existed. New builds recover the precise cause from the
    /// additive key; old builds safely present it as an ordinary local or synced
    /// archive instead of rejecting the whole session.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tab, forKey: .tab)
        try container.encode(archivedAt, forKey: .archivedAt)
        try container.encode(reason.storedReason, forKey: .reason)
        try container.encodeIfPresent(reason.deletionOrigin, forKey: .deletionOrigin)
    }
}
