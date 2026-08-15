import Foundation

struct BrowserExtensionSpaceState: Equatable, Sendable {
    let id: SpaceID
    let tabs: [BrowserExtensionTabState]

    var selectedTabID: TabID? {
        tabs.first(where: \.isSelected)?.id
    }

    func tab(_ id: TabID) -> BrowserExtensionTabState? {
        tabs.first { $0.id == id }
    }
}
