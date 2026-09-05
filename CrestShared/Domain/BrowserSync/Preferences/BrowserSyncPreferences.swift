import Foundation

struct BrowserSyncPreferences: Codable, Equatable, Sendable {
    var savedStructure: Bool
    var currentTabs: Bool
    var historyAndArchive: Bool
    var extensionSettings: Bool

    static let `default` = BrowserSyncPreferences(
        savedStructure: true,
        currentTabs: true,
        historyAndArchive: true,
        extensionSettings: true
    )

    func includes(_ payload: BrowserSyncPayload) -> Bool {
        switch payload {
        case .space:
            true
        case .folder(let folder):
            folder.location == .current ? currentTabs : savedStructure
        case .tab(let tab):
            tab.placement == .current ? currentTabs : savedStructure
        case .history, .archive:
            historyAndArchive
        }
    }
}
