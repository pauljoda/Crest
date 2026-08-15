/// One carry, told apart from every other carry the window has ever had.
///
/// A pickup asks WebKit for a picture before it changes anything on screen, so
/// the request is in flight before there is a carry for it to belong to. The
/// token is what the request holds on to in the meantime: the state hands one out
/// when a pickup is staged, the carry keeps it, and an arriving image is matched
/// against the carry's own token rather than against the tab it pictures.
///
/// A tab is not enough on its own. Picking the same card up twice in quick
/// succession produces two requests for one `TabID`, and the first answer must
/// not be crossfaded into the second carry — it is a picture of a row that has
/// already moved on. Identity per carry says so; identity per tab cannot.
struct BrowserSplitCardLiftToken: Hashable, Sendable {
    /// Monotonic within one window. Never reused, so a stale answer can only
    /// ever fail to match.
    let sequence: UInt64
}
