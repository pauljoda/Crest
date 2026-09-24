import Foundation

/// A rule the core reports breaking, as an answer's `error` member names it.
/// The set stays open: a code this build does not know decodes and falls to
/// each caller's generic failure. Raw values are the core's spellings in
/// `BrowserRuleCodes.cs` and `NativeSyncDocumentErrorCodes.cs`.
struct BrowserCoreErrorCode: RawRepresentable, Hashable, Codable, Sendable {
    // MARK: - Variables

    let rawValue: String

    // Session and workspace rules (`BrowserRuleCodes`).
    static let noIncludedSpaces = BrowserCoreErrorCode(rawValue: "no_included_spaces")
    static let pinnedLimitReached = BrowserCoreErrorCode(rawValue: "pinned_limit_reached")
    static let spaceDeletionInProgress = BrowserCoreErrorCode(rawValue: "space_deletion_in_progress")
    static let spaceLimitReached = BrowserCoreErrorCode(rawValue: "space_limit_reached")
    static let wrongProfileIdentity = BrowserCoreErrorCode(rawValue: "wrong_profile_identity")

    // Sync document queries (`NativeSyncDocumentErrorCodes`).
    static let danglingFolder = BrowserCoreErrorCode(rawValue: "danglingFolder")
    static let duplicateProfile = BrowserCoreErrorCode(rawValue: "duplicateProfile")
    static let duplicateRecord = BrowserCoreErrorCode(rawValue: "duplicateRecord")
    static let immutableProfileChanged = BrowserCoreErrorCode(rawValue: "immutableProfileChanged")
    static let invalidFolderHierarchy = BrowserCoreErrorCode(rawValue: "invalidFolderHierarchy")
    static let recordLimitExceeded = BrowserCoreErrorCode(rawValue: "recordLimitExceeded")
    static let tooManyPinnedTabs = BrowserCoreErrorCode(rawValue: "tooManyPinnedTabs")
}
