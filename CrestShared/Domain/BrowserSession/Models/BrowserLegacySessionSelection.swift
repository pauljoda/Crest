import Foundation

/// The selection earlier releases stored inside the session: the viewed Space and
/// each Space's selected tab. Selection is window state now, so the session no
/// longer carries it. The core answers it with the session it loaded or carried
/// once, so a window without its own record can adopt it, and nothing writes it
/// again.
struct BrowserLegacySessionSelection: Decodable, Equatable, Sendable {
    // MARK: - Types

    private struct Space: Decodable {
        let id: SpaceID
        let selectedTabID: TabID?
    }

    // MARK: - Variables

    let selectedSpaceID: SpaceID?
    let selectedTabIDsBySpace: [SpaceID: TabID]

    var isEmpty: Bool { selectedSpaceID == nil && selectedTabIDsBySpace.isEmpty }

    // MARK: - Initializers

    private enum CodingKeys: String, CodingKey {
        case selectedSpaceID, spaces
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedSpaceID = try? values.decodeIfPresent(SpaceID.self, forKey: .selectedSpaceID)
        let spaces = (try? values.decodeIfPresent([Space].self, forKey: .spaces)) ?? []
        selectedTabIDsBySpace = Dictionary(
            spaces.compactMap { space in space.selectedTabID.map { (space.id, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Actions - Folding

    /// The launch selection a window adopts when it has no record of its own:
    /// the stored tab of every Space that still holds it. Launch has always
    /// opened the default Space, so the stored Space only stands in when the
    /// session names no default.
    func launchSelection(in session: BrowserSession) -> BrowserStoreSelection {
        let tabs = selectedTabIDsBySpace.filter { session.space(id: $0.key)?.contains($0.value) == true }
        let stored = selectedSpaceID.flatMap { session.space(id: $0) }
        let launch = session.defaultSpaceID.flatMap { session.space(id: $0) } ?? stored
        var selection = BrowserStoreSelection(
            selectedSpaceID: launch?.id ?? BrowserStoreSelection(launching: session).selectedSpaceID,
            selectedTabIDsBySpace: tabs)
        if let space = selection.selectedSpace(in: session) { selection.selectSpace(space) }
        return selection
    }
}
