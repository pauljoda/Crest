import Foundation

struct BrowserExtensionTabState: Equatable, Sendable {
    let id: TabID
    let title: String
    let url: URL?
    let placement: TabPlacement
    let index: Int
    let isSelected: Bool
    /// Whether the tab's page has finished loading. Runtime-only state that no
    /// persisted session carries, so a projection built without a live page
    /// reports a settled tab rather than inventing a load.
    let isLoadingComplete: Bool
    /// Whether the tab is currently presenting Crest's reader mode. Runtime-only
    /// for the same reason as `isLoadingComplete`.
    let isReaderModeActive: Bool

    init(
        id: TabID,
        title: String,
        url: URL?,
        placement: TabPlacement,
        index: Int,
        isSelected: Bool,
        isLoadingComplete: Bool = true,
        isReaderModeActive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.placement = placement
        self.index = index
        self.isSelected = isSelected
        self.isLoadingComplete = isLoadingComplete
        self.isReaderModeActive = isReaderModeActive
    }
}
