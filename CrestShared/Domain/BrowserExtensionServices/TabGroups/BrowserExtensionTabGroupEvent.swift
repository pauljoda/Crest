import Foundation

/// A registry change every extension in the same Space observes.
///
/// Chrome's groups are browser-wide: an extension sees, and can update, a
/// group another extension created. Crest keeps that property inside one
/// Space, which is the unit it already presents to extensions as a window.
///
/// Membership changes deliberately do not appear here. Chrome fires
/// `tabGroups.onUpdated` for a group's *visual* data — title, colour, and
/// collapsed state — and reports a tab joining or leaving through the tabs
/// events instead. A store that published `.updated` for every regroup would
/// hand portable packages an event Chrome never sends them.
struct BrowserExtensionTabGroupEvent: Equatable, Sendable {
    /// Separate from visual group events: these are ordinary tab metadata.
    struct Membership: Equatable, Sendable {
        struct Change: Equatable, Sendable {
            let tabID: TabID
            let groupID: BrowserExtensionTabGroupID?
        }

        let spaceID: SpaceID
        let changes: [Change]
    }

    enum Kind: String, Sendable {
        case created
        case updated
        case removed
        case moved
    }

    let kind: Kind
    let group: BrowserExtensionTabGroup

    var spaceID: SpaceID { group.spaceID }
}
