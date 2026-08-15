import Foundation

struct BrowserUtilityListRequest: Equatable, Sendable {
    let surface: BrowserUtilitySurface
    let assignment: BrowserSpaceRuntimeAssignment
    let searchText: String
    let filter: BrowserUtilityListFilter
    let archivedTabs: [ArchivedTab]
    let history: [BrowserHistoryEntry]
    let downloads: [BrowserDownloadItem]
    private let downloadPreparationIdentities: [BrowserUtilityDownloadPreparationIdentity]

    init(
        surface: BrowserUtilitySurface,
        assignment: BrowserSpaceRuntimeAssignment,
        archivedTabs: [ArchivedTab],
        history: [BrowserHistoryEntry],
        downloads: [BrowserDownloadItem],
        searchText: String,
        filter: BrowserUtilityListFilter
    ) {
        let normalizedDownloads = Self.normalizedDownloads(
            downloads,
            profileID: assignment.profileID
        )
        self.surface = surface
        self.assignment = assignment
        self.searchText = searchText
        self.filter = filter
        self.archivedTabs = archivedTabs
        self.history = history
        self.downloads = normalizedDownloads
        downloadPreparationIdentities = normalizedDownloads.map(
            BrowserUtilityDownloadPreparationIdentity.init
        )
    }

    init(
        surface: BrowserUtilitySurface,
        space: BrowserSpace,
        downloads: [BrowserDownloadItem],
        searchText: String,
        filter: BrowserUtilityListFilter
    ) {
        self.init(
            surface: surface,
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            archivedTabs: surface == .archive ? space.archivedTabs : [],
            history: surface == .history ? space.history : [],
            downloads: surface == .downloads ? downloads : [],
            searchText: searchText,
            filter: filter
        )
    }

    static func == (
        lhs: BrowserUtilityListRequest,
        rhs: BrowserUtilityListRequest
    ) -> Bool {
        lhs.surface == rhs.surface
            && lhs.assignment == rhs.assignment
            && lhs.searchText == rhs.searchText
            && lhs.filter == rhs.filter
            && lhs.archivedTabs == rhs.archivedTabs
            && lhs.history == rhs.history
            && lhs.downloadPreparationIdentities
                == rhs.downloadPreparationIdentities
    }

    func hasSamePresentationOwnership(
        as other: BrowserUtilityListRequest
    ) -> Bool {
        surface == other.surface && assignment == other.assignment
    }

    private static func normalizedDownloads(
        _ downloads: [BrowserDownloadItem],
        profileID: UUID
    ) -> [BrowserDownloadItem] {
        var seenIDs: Set<UUID> = []
        return downloads.filter { item in
            item.profileID == profileID && seenIDs.insert(item.id).inserted
        }
    }
}
