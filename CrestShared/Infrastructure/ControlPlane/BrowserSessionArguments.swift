import Foundation

/// The `arguments` member of each session command, in the core's spelling.
/// Identities cross as plain UUIDs (the typed identifiers code as records), and
/// a member the core reads even without a value crosses as an explicit `null`.
enum BrowserSessionArguments {
    // MARK: - Spaces

    /// Space commands that replace one stored value: `space.branding`,
    /// `space.access`, `space.browsing_preferences`,
    /// `space.credential_preferences` and `space.saved_expansion`.
    struct SpaceValue<Value: Encodable>: Encodable {
        let value: Value
    }

    /// `space.create` and `space.reset_private`: the native presentation
    /// defaults the new Space starts from.
    struct SpaceTemplate: Encodable {
        let template: BrowserSpace
    }

    /// `space.identity`.
    struct SpaceIdentity: Encodable, Sendable {
        let name: String
        let symbol: String
        let accent: SpaceAccent
    }

    /// `space.reorder`.
    struct SpaceReorder: Encodable, Sendable {
        let offsets: [Int]
        let destination: Int
    }

    /// `space.deletion.begin` and `space.remove`.
    struct SpaceDeletion: Encodable, Sendable {
        let operationID: UUID
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
