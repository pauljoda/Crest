/// What Crest does about one external-scheme hand-off once consent is known.
enum BrowserExternalSchemeConsent: Equatable, Sendable {
    case open
    case prompt
    case block

    /// A hand-off launches another application, so an unapproved request always
    /// pauses at Crest's consent prompt. Script-mediated app links are common on
    /// meeting and sign-in pages; they may ask, but they cannot launch anything
    /// until a person approves the destination.
    static func resolve(
        trigger: BrowserPopupTrigger,
        decision: BrowserSitePermissionDecision
    ) -> BrowserExternalSchemeConsent {
        switch decision {
        case .grantForSession, .grantPersistently:
            return .open
        case .denyForSession, .denyPersistently:
            return .block
        case .ask:
            return .prompt
        }
    }
}
