import Foundation

enum BrowserUtilityListFilter: Hashable, Identifiable, Sendable {
    case all
    case archivedClosed
    case archivedAutomatically
    case archivedQuickWindow
    case historyToday
    case historyPastWeek
    case historyPastMonth
    case downloadsInProgress
    case downloadsFinished
    case downloadsNeedsAttention

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .archivedClosed: "Closed"
        case .archivedAutomatically: "Automatically Cleaned"
        case .archivedQuickWindow: "Quick Windows"
        case .historyToday: "Today"
        case .historyPastWeek: "Past Week"
        case .historyPastMonth: "Past Month"
        case .downloadsInProgress: "In Progress"
        case .downloadsFinished: "Finished"
        case .downloadsNeedsAttention: "Needs Attention"
        }
    }

    static func options(for surface: BrowserUtilitySurface) -> [Self] {
        switch surface {
        case .archive:
            [
                .all,
                .archivedClosed,
                .archivedAutomatically,
                .archivedQuickWindow,
            ]
        case .history:
            [.all, .historyToday, .historyPastWeek, .historyPastMonth]
        case .downloads:
            [
                .all,
                .downloadsInProgress,
                .downloadsFinished,
                .downloadsNeedsAttention,
            ]
        }
    }

    func normalized(for surface: BrowserUtilitySurface) -> Self {
        Self.options(for: surface).contains(self) ? self : .all
    }
}
