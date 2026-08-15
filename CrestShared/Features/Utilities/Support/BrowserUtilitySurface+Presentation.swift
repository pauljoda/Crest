import Foundation

extension BrowserUtilitySurface {
    var title: LocalizedStringResource {
        switch self {
        case .archive: "Archive"
        case .history: "History"
        case .downloads: "Downloads"
        }
    }

    var systemImage: String {
        switch self {
        case .archive: "archivebox"
        case .history: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        }
    }

    var searchPrompt: LocalizedStringResource {
        switch self {
        case .archive: "Search Archive…"
        case .history: "Search History…"
        case .downloads: "Search Downloads…"
        }
    }

    var emptyTitle: LocalizedStringResource {
        switch self {
        case .archive: "No Archived Tabs"
        case .history: "No History"
        case .downloads: "No Downloads"
        }
    }

    var emptyDescription: LocalizedStringResource {
        switch self {
        case .archive:
            "Closed and automatically cleaned tabs from this Space appear here."
        case .history:
            "Completed visits from this Space appear here and remain separate from every other Space."
        case .downloads:
            "Downloads from this Space appear here."
        }
    }

    func noResultsDescription(matching query: String) -> LocalizedStringResource {
        switch self {
        case .archive:
            "No archived tabs in this Space match “\(query)”."
        case .history:
            "No history entries in this Space match “\(query)”."
        case .downloads:
            "No downloads in this Space match “\(query)”."
        }
    }

    var filterLabel: LocalizedStringResource {
        switch self {
        case .archive: "Filter Archive"
        case .history: "Filter History"
        case .downloads: "Filter Downloads"
        }
    }
}
