import Foundation

enum BrowserSyncError: Error, Equatable {
    case unsupportedSchema(Int)
    case invalidRecord(String)
    case recordIdentityMismatch(String)
    case duplicateRecord(String)
    case crossSpaceConflict(String)
    case invalidURL(String)
    case invalidField(String)
    case immutableProfileChanged(SpaceID)
    case duplicateProfile(UUID)
    case tooManyPinnedTabs(SpaceID)
    case danglingFolder(TabID)
    case invalidFolderHierarchy(SpaceID)
    case recordLimitExceeded(Int)
    case logicalClockExhausted
    /// A change that arrived from another device could not be applied. Sync
    /// reports this instead of finishing a cycle that dropped records.
    case remoteChangeNotApplied(String)
    /// This build cannot read the device's sync journal, for the reason given,
    /// which names a record or a field but never what a record holds. Sync is
    /// paused until the core accepts a journal it can read.
    case unreadableJournal(String)
}
