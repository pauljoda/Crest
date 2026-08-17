/// Describes what one session save actually has to rewrite.
///
/// A save used to mean "re-encode the whole graph": every Space's tabs and
/// archived tabs, every favicon blob, and up to
/// `BrowserSession.maximumHistoryEntriesPerSpace` history entries per Space. A
/// page mutating `document.title` in a loop drove that continuously, because a
/// title change and a cleared history were the same write. The scope is how a
/// mutation says what it touched, so a title change rewrites the small session
/// core and nothing else.
///
/// An unclassified save is `.everything`. Narrowing a scope buys performance, so
/// forgetting to narrow one costs performance and never durability.
struct BrowserSessionSaveScope: Equatable, Sendable {

    /// Whether the light session core — Spaces with their tabs, folders,
    /// branding, and preferences — is rewritten.
    var writesCore: Bool
    /// Which Spaces' history lists are rewritten.
    var history: BrowserSessionSaveSelection<SpaceID>
    /// Which tabs' favicons are reconciled against the side store.
    var favicons: BrowserSessionSaveSelection<TabID>

    /// Rewrites everything. The safe default for a mutation nobody has
    /// classified, and what a launch, an import, and a remote merge all need.
    static let everything = Self(
        writesCore: true,
        history: .everything,
        favicons: .everything
    )

    /// Rewrites the session core alone: selection, tab order, folders, titles,
    /// branding, preferences. History and favicon bytes are left untouched.
    static let core = Self(writesCore: true, history: .nothing, favicons: .nothing)

    /// Rewrites one Space's history and nothing else. A visit changes no core
    /// state, so the core blob is not re-encoded either.
    static func history(in spaceID: SpaceID) -> Self {
        Self(writesCore: false, history: .only([spaceID]), favicons: .nothing)
    }

    /// Reconciles one tab's favicon, and rewrites the core because the fields
    /// that frame an icon — `symbol`, `faviconURL`, `iconAccent`, `iconMode` —
    /// live there. History is untouched: the core no longer carries either
    /// history or icon bytes, so this is a small write even for a busy tab.
    static func favicon(for tabID: TabID) -> Self {
        Self(writesCore: true, history: .nothing, favicons: .only([tabID]))
    }
}
