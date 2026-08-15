import CoreGraphics

/// Everything the split surface's pointer monitor can do to a carry, and the one
/// thing it may ask about one.
///
/// Closures rather than a delegate, and a value rather than an object, because
/// the split between the two sides is total: the monitor owns the event stream
/// and nothing else, and every decision — which card a point is in, whether the
/// row can spare one, what the session should be told on release — belongs to
/// the view that already holds the frames, the members, and the store.
///
/// `begin` answers whether a card was picked up, which is also the monitor's
/// answer to whether it should keep the event. A refused pickup is an ordinary
/// click and continues to the page untouched.
///
/// `isCarrying` is asked rather than remembered, and that is the important one.
/// A monitor that kept its own copy of "a card is on the pointer" would be
/// keeping a second answer to a question the lift state already answers — and a
/// second answer can be left behind. Every way a carry can end without passing
/// through the monitor (the card leaving the row, the window going away, the
/// state being abandoned outright) would strand that copy at `true`, and a
/// monitor that believes it is carrying swallows every press that follows.
struct BrowserSplitCardLiftGesture {
    let begin: @MainActor @Sendable (CGPoint, BrowserKeyboardModifierFlags) -> Bool
    let update: @MainActor @Sendable (CGPoint) -> Void
    let drop: @MainActor @Sendable () -> Void
    let cancel: @MainActor @Sendable () -> Void
    /// Whether a card is on the pointer at this instant, straight from the state
    /// that owns the carry.
    let isCarrying: @MainActor @Sendable () -> Bool
}
