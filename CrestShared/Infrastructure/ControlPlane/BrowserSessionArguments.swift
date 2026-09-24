import Foundation

/// The `arguments` member of each session command, in the core's spelling.
/// Identities cross as plain UUIDs (the typed identifiers code as records), and
/// a member the core reads even without a value crosses as an explicit `null`.
enum BrowserSessionArguments {
    // MARK: - Spaces

    /// Space commands that replace one stored value: `space.browsing_preferences`.
    struct SpaceValue<Value: Encodable>: Encodable {
        let value: Value
    }

    /// `space.search_provider.upsert`.
    struct SearchProviderUpsert: Encodable, Sendable {
        let provider: BrowserCoreSearchProviderRecord
        let selects: Bool
    }

    /// `space.search_provider.remove`, with the engine's core identity.
    struct SearchProviderRemove: Encodable, Sendable {
        let id: String
    }
}
