import Foundation

struct PortableArchivedTab: Codable, Equatable, Sendable {
    let tab: PortableTab
    let archivedAt: Date
    let reason: TabArchiveReason

    init(_ archivedTab: ArchivedTab) {
        tab = PortableTab(archivedTab.tab)
        archivedAt = archivedTab.archivedAt
        reason = archivedTab.reason
    }

    func materialize() throws -> ArchivedTab {
        try ArchiveValidation.requireDate(archivedAt)
        let materializedTab = try tab.materialize(folderIDsBySourceID: [:])
        guard materializedTab.placement == .current else {
            throw BrowserPortableArchiveError.invalidContents
        }
        return ArchivedTab(
            tab: materializedTab,
            archivedAt: archivedAt,
            reason: reason
        )
    }
}
