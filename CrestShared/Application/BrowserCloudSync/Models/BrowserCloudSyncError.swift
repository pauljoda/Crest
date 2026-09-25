import Foundation

/// Why the cloud transport stopped a step.
enum BrowserCloudSyncError: Error, Equatable {
    /// A change that arrived from another device could not be applied. Sync
    /// reports this instead of finishing a cycle that dropped records.
    case remoteChangeNotApplied(String)
}
