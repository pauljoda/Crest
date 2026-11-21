import Foundation

/// Where a reviewed Space goes: a new Space, or the existing Space it joins.
enum BrowserImportDestination: Equatable, Hashable, Sendable {
    case newSpace
    case existing(UUID)

    /// The existing Space it joins, or nil for a new Space.
    var spaceID: UUID? {
        switch self {
        case .newSpace: nil
        case .existing(let id): id
        }
    }
}

/// One Space of the review the core holds, as the review views draw it: the
/// Space the browser brought, held by no workspace, with the person's choices
/// and what the core says they mean. It holds nothing of its own; the flow
/// builds it from the core's review each time the review changes.
struct BrowserImportSpaceReview: Identifiable, Equatable {
    // MARK: - Variables

    let record: SetupReviewSpace
    /// The Space the browser brought, as the review views draw it.
    let sourceSpace: SpaceModel

    var id: UUID { record.source.id }
    var isIncluded: Bool { record.included }
    var includesPasswords: Bool { record.includesPasswords }
    /// The extensions the Space offers to install, and those left on.
    var extensions: [ImportExtension] { record.extensions }
    var includedExtensionIDs: Set<String> { Set(record.includedExtensionIDs) }
    var includedTabIDs: Set<UUID> { Set(record.includedTabIDs) }
    var duplicateTabIDs: Set<UUID> { Set(record.duplicateTabIDs) }
    var destination: BrowserImportDestination {
        record.destinationID.map(BrowserImportDestination.existing) ?? .newSpace
    }
    /// The name, symbol and look the Space takes.
    var customization: SpaceCustomization { record.customization }
    /// The group the Space comes into: the primary of the workspace's group
    /// it joins, or else the reviewed Space that leads the Spaces it shared a
    /// session with where it came from, or itself.
    var groupID: UUID { record.joinsGroupOf ?? record.source.membership?.primaryID ?? record.source.id }

    // MARK: - Initializers

    @MainActor
    init(_ record: SetupReviewSpace) {
        self.record = record
        sourceSpace = SpaceModel(record.source)
    }

    // MARK: - Actions - Tabs

    /// The placement `tab` comes in with: the one the person chose, or its own.
    @MainActor
    func placement(for tab: TabStateModel) -> TabPlacement {
        record.placements.last { $0.tabID == tab.id }?.placement ?? tab.placement
    }

    /// Two reviews are equal when the core's records are: the Space drawn
    /// is read from the record.
    static func == (lhs: BrowserImportSpaceReview, rhs: BrowserImportSpaceReview) -> Bool {
        lhs.record == rhs.record
    }
}
