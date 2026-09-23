import Foundation

/// Which tab a window shows for a Space after the core repairs it.
enum BrowserWindowTabSelection: String, Decodable {
    case window
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
    // MARK: - Types

    struct WindowSpaceFacts {
        let id: SpaceID
        let hasWindowTab: Bool
        let isCaptured: Bool
        let hasTabs: Bool
    }

    struct WindowSplitLayout {
        let groupID: SplitGroupID
        let columns: Int
        let liveMembers: Int?
    }

    private struct RepairRequest: Encodable {
        struct Space: Encodable {
            let id: String
            let windowTab: Bool
            let captured: Bool
            let hasTabs: Bool
        }

        struct SplitLayout: Encodable {
            let groupID: String
            let columns: Int
            @BrowserCoreNullable var liveMembers: Int?
        }

        let selectedSpaceID: String
        let capturesSelection: Bool
        let spaces: [Space]
        let splitLayouts: [SplitLayout]
    }

    private struct RepairAnswer: Decodable {
        let selectedSpaceID: UUID
        let selections: [BrowserWindowTabSelection]
        let splitLayouts: BrowserCoreKnownValues<UUID>
        @BrowserCoreOptional var capturedSpaceIDs: BrowserCoreKnownValues<UUID>?
    }

    private struct SplitFractionsRequest: Encodable {
        let fractions: [Double]
    }

    private struct SplitFractionsAnswer: Decodable {
        let fractions: [Double]
    }

    private struct TearOffRequest: Encodable {
        let spaceMatches: Bool
        let spaceLocked: Bool
        let containsTab: Bool
        @BrowserCoreNullable var selectionCount: Int?
        let selectionIncludesTab: Bool
    }

    private struct TearOffAnswer: Decodable {
        @BrowserCoreOptional var allowed: Bool?
    }

    private struct SelectionFallbackRequest: Encodable {
        let placements: [TabPlacement]
    }

    private struct SelectionFallbackAnswer: Decodable {
        let index: Int
    }

    // MARK: - Actions - Windows

    /// Nil when the core cannot answer; the caller keeps its state untouched.
    static func windowRepair(
        selectedSpaceID: SpaceID, capturesSelection: Bool,
        spaces: [WindowSpaceFacts], splitLayouts: [WindowSplitLayout]
    ) -> BrowserWindowRepair? {
        let request = RepairRequest(
            selectedSpaceID: selectedSpaceID.rawValue.coreIdentifier,
            capturesSelection: capturesSelection,
            spaces: spaces.map { space in
                RepairRequest.Space(
                    id: space.id.rawValue.coreIdentifier, windowTab: space.hasWindowTab, captured: space.isCaptured,
                    hasTabs: space.hasTabs)
            },
            splitLayouts: splitLayouts.map { layout in
                RepairRequest.SplitLayout(
                    groupID: layout.groupID.rawValue.coreIdentifier, columns: layout.columns,
                    liveMembers: layout.liveMembers)
            })
        guard let answer = evaluate(.windowRepair, request, answer: RepairAnswer.self),
            answer.selections.count == spaces.count
        else { return nil }
        return BrowserWindowRepair(
            selectedSpaceID: answer.selectedSpaceID, selections: answer.selections,
            splitLayoutGroupIDs: Set(answer.splitLayouts.values),
            capturedSpaceIDs: answer.capturedSpaceIDs?.values)
    }

    /// The column shares to store for one split group, or nil when they cannot
    /// describe columns or the core cannot answer.
    static func splitColumnFractions(_ fractions: [Double]) -> [Double]? {
        guard fractions.allSatisfy(\.isFinite) else { return nil }
        return evaluate(
            .windowSplitLayout, SplitFractionsRequest(fractions: fractions), answer: SplitFractionsAnswer.self)?
            .fractions
    }

    /// Whether a dragged tab may leave its window. An unavailable core keeps
    /// the tab where it is.
    static func allowsTearOff(
        spaceMatches: Bool, spaceLocked: Bool, containsTab: Bool,
        selection: [TabID]?, tabID: TabID
    ) -> Bool {
        let request = TearOffRequest(
            spaceMatches: spaceMatches, spaceLocked: spaceLocked, containsTab: containsTab,
            selectionCount: selection?.count, selectionIncludesTab: selection?.contains(tabID) == true)
        return evaluate(.windowTearOff, request, answer: TearOffAnswer.self)?.allowed ?? false
    }

    /// Index into `placements` of the tab a Space selects when its selection is
    /// gone. Nil when the core cannot answer or there is no candidate.
    static func selectionFallback(placements: [TabPlacement]) -> Int? {
        guard
            let index = evaluate(
                .tabsSelectionFallback, SelectionFallbackRequest(placements: placements),
                answer: SelectionFallbackAnswer.self)?.index,
            placements.indices.contains(index)
        else { return nil }
        return index
    }
}
