/// The answer to one external-app prompt. Cancelling is deliberately not a
/// remembered block: a person declining one hand-off has not asked Crest to
/// refuse every future one, which Site Permissions is there for.
enum BrowserExternalSchemePromptResponse: Equatable, Sendable {
    case open
    case openAndRemember
    case cancel
}
