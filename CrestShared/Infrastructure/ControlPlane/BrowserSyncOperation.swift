import Foundation

/// One sync journal mutation, sync query or stateless sync evaluation. Raw
/// values are the core's spellings in `NativeSyncOperation.cs`.
enum BrowserSyncOperation: String, Codable, Sendable {
    case merge
    case replace
    case overwrite
    case stage
    case acknowledge
    case preferences
    case resolve
    case reconcile
    case orderAllocate = "order.allocate"
    case project
    case materialize
    case sessionRepair = "session.repair"
}
