/// What a page observation actually changed. The store needs the tab whose
/// stored image moved, so a title rewrite does not rewrite the favicon store.
struct BrowserTabObservation: Equatable, Sendable {
    var tabID: TabID
    var changedFavicon: Bool
}
