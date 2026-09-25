import Foundation

/// A rule the core reports breaking, as an answer's `error` member names it.
/// The set stays open: a code this build does not know decodes and falls to
/// each caller's generic failure. Raw values are the core's spellings in
/// `BrowserRuleCodes.cs`.
struct BrowserCoreErrorCode: RawRepresentable, Hashable, Codable, Sendable {
    // MARK: - Variables

    let rawValue: String

    // The manual-setup tab policy (`BrowserRuleCodes`).
    static let pinnedLimitReached = BrowserCoreErrorCode(rawValue: "pinned_limit_reached")
}
