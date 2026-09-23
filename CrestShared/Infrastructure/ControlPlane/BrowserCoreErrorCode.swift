import Foundation

/// A rule the core reports breaking, as an answer's `error` member names it.
/// The set stays open: a code this build does not know decodes and falls to
/// each caller's generic failure. Raw values are the core's spellings in
/// `BrowserRuleCodes.cs`, `NativeSyncDocumentErrorCodes.cs` and the tab-batch
/// rules of `BrowserTabCollection.Batch.cs`.
struct BrowserCoreErrorCode: RawRepresentable, Hashable, Codable, Sendable {
    // MARK: - Variables

    let rawValue: String

    // Session and workspace rules (`BrowserRuleCodes`).
    static let folderActionUnavailable = BrowserCoreErrorCode(rawValue: "folder_action_unavailable")
    static let incompleteSplit = BrowserCoreErrorCode(rawValue: "incomplete_split")
    static let noIncludedSpaces = BrowserCoreErrorCode(rawValue: "no_included_spaces")
    static let pinnedLimit = BrowserCoreErrorCode(rawValue: "pinned_limit")
    static let pinnedLimitReached = BrowserCoreErrorCode(rawValue: "pinned_limit_reached")
    static let spaceDeletionInProgress = BrowserCoreErrorCode(rawValue: "space_deletion_in_progress")
    static let spaceLimitReached = BrowserCoreErrorCode(rawValue: "space_limit_reached")
    static let splitLimit = BrowserCoreErrorCode(rawValue: "split_limit")
    static let staleSelection = BrowserCoreErrorCode(rawValue: "stale_selection")
    static let unknownFolder = BrowserCoreErrorCode(rawValue: "unknown_folder")
    static let unknownSpace = BrowserCoreErrorCode(rawValue: "unknown_space")
    static let unknownTab = BrowserCoreErrorCode(rawValue: "unknown_tab")
    static let wrongProfileIdentity = BrowserCoreErrorCode(rawValue: "wrong_profile_identity")

    // Tab batch rules, raised by the batch itself rather than `BrowserRuleCodes`.
    static let cannotMoveSplitAcrossSpaces = BrowserCoreErrorCode(rawValue: "cannot_move_split_across_spaces")
    static let cannotPinSplit = BrowserCoreErrorCode(rawValue: "cannot_pin_split")
    static let currentTabsOnly = BrowserCoreErrorCode(rawValue: "current_tabs_only")
    static let pinnedCapacity = BrowserCoreErrorCode(rawValue: "pinned_capacity")
    static let splitCapacity = BrowserCoreErrorCode(rawValue: "split_capacity")
    static let webPagesOnly = BrowserCoreErrorCode(rawValue: "web_pages_only")

    // Sync document queries (`NativeSyncDocumentErrorCodes`).
    static let danglingFolder = BrowserCoreErrorCode(rawValue: "danglingFolder")
    static let duplicateProfile = BrowserCoreErrorCode(rawValue: "duplicateProfile")
    static let duplicateRecord = BrowserCoreErrorCode(rawValue: "duplicateRecord")
    static let immutableProfileChanged = BrowserCoreErrorCode(rawValue: "immutableProfileChanged")
    static let invalidFolderHierarchy = BrowserCoreErrorCode(rawValue: "invalidFolderHierarchy")
    static let recordLimitExceeded = BrowserCoreErrorCode(rawValue: "recordLimitExceeded")
    static let tooManyPinnedTabs = BrowserCoreErrorCode(rawValue: "tooManyPinnedTabs")
}
