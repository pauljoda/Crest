import Foundation

extension CrestCore {
    /// The tab a Space shows when no window chose one, by the core's rule: the
    /// first open tab, else the first pinned one, else the first tab. For a
    /// Space value no window shows, such as a draft or a preview.
    func fallbackTabID(in space: BrowserSpace) -> TabID? {
        guard let index = (try? query(FallbackTab(placements: space.tabs.map(\.placement))))?.index,
            space.tabs.indices.contains(index)
        else { return nil }
        return space.tabs[index].id
    }
}
