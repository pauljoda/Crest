/// Which engine, if any, owns a navigation once its URL scheme is known.
enum BrowserExternalSchemeDisposition: Equatable, Sendable {
    /// WebKit's to load — or to refuse on its own terms.
    case webKit
    /// Neither WebKit nor another app may see it.
    case blocked
    /// Another application owns the scheme. Crest cancels and hands it to the OS.
    case handOff
}
