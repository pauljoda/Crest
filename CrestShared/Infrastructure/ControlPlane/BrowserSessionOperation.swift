import Foundation

/// One command of the family's core session. Raw values are the core's
/// spellings in `SessionOperation.cs`.
enum BrowserSessionOperation: String, Codable, Sendable {
    case tabTransfer = "tab.transfer"
    case tabsBatch = "tabs.batch"
    case workspaceImport = "workspace.import"
}
