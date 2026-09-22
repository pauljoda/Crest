import Foundation

/// Which tab a window shows for a Space after the core repairs it.
enum BrowserWindowTabSelection: String {
    case window
    case space
    case first
    case none
}

/// The core's answer to a window-state repair, in the order the Spaces were sent.
struct BrowserWindowRepair {
    let selectedSpaceID: UUID
    let selections: [BrowserWindowTabSelection]
    let splitLayoutGroupIDs: Set<UUID>
    let capturedSpaceIDs: [UUID]?
}

/// Window selection, split layout and tear-off rules owned by the portable core.
/// Window state is device-local: requests carry identities and presence facts,
/// never tab contents.
extension BrowserCorePolicy {
    struct WindowSpaceFacts {
        let id: SpaceID
        let hasWindowTab: Bool
        let isCaptured: Bool
        let hasSpaceSelection: Bool
        let hasTabs: Bool
    }

    struct WindowSplitLayout {
        let groupID: SplitGroupID
        let columns: Int
        let liveMembers: Int?
    }

    /// Nil when the core cannot answer; the caller keeps its state untouched.
    static func windowRepair(selectedSpaceID: SpaceID, sessionSelectedSpaceID: SpaceID, capturesSelection: Bool,
        spaces: [WindowSpaceFacts], splitLayouts: [WindowSplitLayout]) -> BrowserWindowRepair? {
        guard let response = evaluate([
            "version": 1, "operation": "window.repair",
            "selectedSpaceID": selectedSpaceID.rawValue.coreIdentifier,
            "sessionSelectedSpaceID": sessionSelectedSpaceID.rawValue.coreIdentifier,
            "capturesSelection": capturesSelection,
            "spaces": spaces.map { space -> [String: Any] in
                ["id": space.id.rawValue.coreIdentifier, "windowTab": space.hasWindowTab, "captured": space.isCaptured,
                 "spaceSelection": space.hasSpaceSelection, "hasTabs": space.hasTabs]
            },
            "splitLayouts": splitLayouts.map { layout -> [String: Any] in
                ["groupID": layout.groupID.rawValue.coreIdentifier, "columns": layout.columns,
                 "liveMembers": layout.liveMembers as Any? ?? NSNull()]
            },
        ]), let selected = (response["selectedSpaceID"] as? String).flatMap(UUID.init(uuidString:)),
            let names = response["selections"] as? [String], names.count == spaces.count,
            let layouts = response["splitLayouts"] as? [String]
        else { return nil }
        let selections = names.compactMap(BrowserWindowTabSelection.init(rawValue:))
        guard selections.count == names.count else { return nil }
        let captured = response["capturedSpaceIDs"] as? [String]
        return BrowserWindowRepair(selectedSpaceID: selected, selections: selections,
            splitLayoutGroupIDs: Set(layouts.compactMap(UUID.init(uuidString:))),
            capturedSpaceIDs: captured?.compactMap(UUID.init(uuidString:)))
    }

    /// The column shares to store for one split group, or nil when they cannot
    /// describe columns or the core cannot answer.
    static func splitColumnFractions(_ fractions: [Double]) -> [Double]? {
        guard fractions.allSatisfy(\.isFinite) else { return nil }
        return evaluate(["version": 1, "operation": "window.split_layout", "fractions": fractions])?["fractions"] as? [Double]
    }

    /// Whether a dragged tab may leave its window. An unavailable core keeps
    /// the tab where it is.
    static func allowsTearOff(spaceMatches: Bool, spaceLocked: Bool, containsTab: Bool,
        selection: [TabID]?, tabID: TabID) -> Bool {
        evaluate([
            "version": 1, "operation": "window.tear_off", "spaceMatches": spaceMatches, "spaceLocked": spaceLocked,
            "containsTab": containsTab, "selectionCount": selection?.count as Any? ?? NSNull(),
            "selectionIncludesTab": selection?.contains(tabID) == true,
        ])?["allowed"] as? Bool ?? false
    }

    /// Index into `placements` of the tab a Space selects when its selection is
    /// gone. Nil when the core cannot answer or there is no candidate.
    static func selectionFallback(placements: [TabPlacement]) -> Int? {
        guard let index = evaluate(["version": 1, "operation": "tabs.selection_fallback",
            "placements": placements.map(\.rawValue)])?["index"] as? Int,
            placements.indices.contains(index) else { return nil }
        return index
    }
}

extension UUID {
    /// The spelling core policy requests require for identities.
    var coreIdentifier: String { uuidString.lowercased() }
}
