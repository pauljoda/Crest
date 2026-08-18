import Foundation

struct ArchivedTab: Codable, Equatable, Identifiable, Sendable {
    var id: TabID { tab.id }
    var tab: BrowserTab
    var archivedAt: Date
    var reason: TabArchiveReason

    init(tab: BrowserTab, archivedAt: Date, reason: TabArchiveReason) {
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

    private enum DeletionOrigin: String, Codable {
        case local
        case remote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tab = try container.decode(BrowserTab.self, forKey: .tab)
        archivedAt = try container.decode(Date.self, forKey: .archivedAt)
        let storedReason = container.decodeTolerantly(
            .reason,
            default: TabArchiveReason.closed
        )
        reason =
            switch try container.decodeIfPresent(
                DeletionOrigin.self,
                forKey: .deletionOrigin
            ) {
            case .local: .deleted
            case .remote: .deletedOnAnotherDevice
            case nil: storedReason
            }
    }

    /// Keep the required `reason` term readable by builds shipped before
    /// deletion audits existed. New builds recover the precise cause from the
    /// additive key; old builds safely present it as an ordinary local or synced
    /// archive instead of rejecting the whole session.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tab, forKey: .tab)
        try container.encode(archivedAt, forKey: .archivedAt)
        switch reason {
        case .deleted:
            try container.encode(TabArchiveReason.closed, forKey: .reason)
            try container.encode(DeletionOrigin.local, forKey: .deletionOrigin)
        case .deletedOnAnotherDevice:
            try container.encode(TabArchiveReason.synced, forKey: .reason)
            try container.encode(DeletionOrigin.remote, forKey: .deletionOrigin)
        default:
            try container.encode(reason, forKey: .reason)
        }
    }
}
