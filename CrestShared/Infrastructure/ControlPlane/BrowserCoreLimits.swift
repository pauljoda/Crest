import Foundation

/// The capacity limits the core enforces, read once through the `limits`
/// policy operation. Native surfaces use these to shape their UI (disable a pin
/// action, stop offering a nested folder); the core still rejects anything past
/// them, so these are never a second implementation of the rule.
struct BrowserCoreLimits: Decodable, Equatable, Sendable {
    // MARK: - Variables

    let pinnedTabs: Int
    let folders: Int
    let folderDepth: Int
    let historyEntries: Int
    let splitMembers: Int
    let brandColors: Int
    let crestPalette: Int
    let spaces: Int
    let tabsPerSpace: Int
    let syncRecords: Int

    /// The packaged core's limits. The core ships inside every composition, so
    /// a missing answer is a broken build rather than a state to recover from.
    static let current: BrowserCoreLimits = {
        guard let response = BrowserCorePolicy.evaluate(["version": 1, "operation": "limits"]),
            let data = try? JSONSerialization.data(withJSONObject: response),
            let limits = try? JSONDecoder().decode(BrowserCoreLimits.self, from: data)
        else { preconditionFailure("The core did not report its limits") }
        return limits
    }()
}
