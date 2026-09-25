#if DEBUG || CREST_PERFORMANCE_HARNESS
    import Foundation

    /// S6.4 spike, DEBUG and performance builds only: the composed session the
    /// sidebar spike measures beside the performance soak's heavy one.
    enum ReadModelSpikeFixture {
        // MARK: - Static Variables

        private static let spaceCount = 3
        private static let pinnedCount = 12
        private static let savedPerFolder = 5
        private static let splitCount = 3
        private static let currentCount = 60
        private static let historyCount = 2_000
        private static let firstVisit = Date(timeIntervalSince1970: 1_750_000_000)

        // MARK: - Actions - Sessions

        /// Three Spaces, each with 12 pinned tabs, 40 saved tabs in 8 folders
        /// nested up to 3 deep, 3 splits of two current tabs and 60 current
        /// tabs in all. The first Space also keeps 2,000 history entries.
        static func composed() -> BrowserSession {
            BrowserSession(
                spaces: (0..<spaceCount).map { index in
                    space(index, history: index == 0 ? historyCount : 0)
                })
        }

        private static func space(_ index: Int, history historyCount: Int) -> BrowserSpace {
            let folders = folders(in: index)
            var tabs = (0..<pinnedCount).map { tab("Pinned \(index)-\($0)", placement: .pinned) }
            for (folderIndex, folder) in folders.enumerated() {
                tabs += (0..<savedPerFolder).map {
                    tab("Saved \(index)-\(folderIndex)-\($0)", placement: .saved, folderID: folder.id)
                }
            }
            for position in 0..<currentCount {
                let split = position < splitCount * 2 ? splitGroupIDs(in: index)[position / 2] : nil
                tabs.append(tab("Current \(index)-\(position)", placement: .current, splitGroupID: split))
            }
            let history = (0..<historyCount).map { visit in
                BrowserHistoryEntry(
                    url: URL(string: "https://history.example/\(index)/\(visit)")!, title: "Visit \(visit)",
                    firstVisitedAt: firstVisit.addingTimeInterval(Double(visit)),
                    lastVisitedAt: firstVisit.addingTimeInterval(Double(visit)))
            }
            return BrowserSpace(
                id: SpaceID(), profile: BrowsingProfile(), name: "Space \(index)", symbol: "square.stack",
                accent: SpaceAccent.all[index % SpaceAccent.all.count], folders: folders, tabs: tabs,
                history: history)
        }

        /// Eight saved folders in three chains: two three deep and one two
        /// deep.
        private static func folders(in index: Int) -> [BrowserFolder] {
            var folders: [BrowserFolder] = []
            for chain in [3, 3, 2] {
                var parentID: FolderID?
                for depth in 0..<chain {
                    let folder = BrowserFolder(
                        title: "Folder \(index)-\(folders.count) depth \(depth)", parentID: parentID)
                    folders.append(folder)
                    parentID = folder.id
                }
            }
            return folders
        }

        private static func splitGroupIDs(in index: Int) -> [SplitGroupID] {
            (0..<splitCount).map { UUID(uuidString: String(format: "5B11D000-0000-4000-8000-%012d", index * 10 + $0))! }
        }

        private static func tab(
            _ title: String, placement: TabPlacement, folderID: FolderID? = nil, splitGroupID: SplitGroupID? = nil
        ) -> BrowserTab {
            let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
            return BrowserTab(
                title: title, url: URL(string: "https://\(slug).example/"), placement: placement,
                folderID: folderID, splitGroupID: splitGroupID)
        }
    }
#endif
