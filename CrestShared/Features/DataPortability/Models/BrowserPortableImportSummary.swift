import Foundation

struct BrowserPortableImportSummary: Equatable, Sendable {
    let spaceCount: Int
    let folderCount: Int
    let liveTabCount: Int
    let archivedTabCount: Int
    let historyEntryCount: Int

    var conciseDescription: String {
        "\(spaceCount.formatted()) \(spaceCount == 1 ? "Space" : "Spaces"), "
            + "\(liveTabCount.formatted()) tabs, "
            + "\(historyEntryCount.formatted()) history entries"
    }
}
