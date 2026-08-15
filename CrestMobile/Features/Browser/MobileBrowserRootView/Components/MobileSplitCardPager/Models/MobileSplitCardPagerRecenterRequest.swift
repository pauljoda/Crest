/// A deferred request to put the carousel back on the focused card.
///
/// Membership changing — a member closed, a group dissolved remotely, a fourth
/// card arriving from another device — can leave the scroll view resting on an
/// offset that no longer belongs to any card. Recentring has to happen after
/// SwiftUI has laid the new run out, and by then a second change may already
/// have arrived; carrying the revision and the card it was made for is what lets
/// the late work recognize that it is stale and do nothing.
struct MobileSplitCardPagerRecenterRequest: Equatable, Sendable {
    let revision: UInt
    let tabID: TabID

    func isCurrent(revision: UInt, focusedTabID: TabID?) -> Bool {
        self.revision == revision && tabID == focusedTabID
    }
}
