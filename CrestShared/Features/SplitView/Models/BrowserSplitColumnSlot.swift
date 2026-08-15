/// One column of the split-view row.
///
/// A drag in flight adds a column rather than decorating the row with one. The
/// slot the dragged tab would land in is laid out, wrapped, and measured exactly
/// as a member's card is: same surface, same gap, same share of the container.
/// Only its interior differs, and only until the drop replaces it with the card
/// it was standing in for.
///
/// Identity is what makes that replacement read as a replacement. A member keeps
/// its `TabID` for the life of the row, so the cards a drag never touched are
/// never remounted — which matters more here than in an ordinary list, because a
/// remounted card would hand a live `WKWebView` to a second superview. The
/// placeholder is the one slot with no tab behind it, so `nil` is its identity:
/// on release the placeholder leaves and the joining member arrives in the same
/// position at the same width, and every other column holds still.
enum BrowserSplitColumnSlot: Identifiable {
    case member(BrowserTab)
    /// The column a drag in flight would drop into.
    case placeholder

    var id: TabID? {
        switch self {
        case .member(let tab): tab.id
        case .placeholder: nil
        }
    }

    var member: BrowserTab? {
        switch self {
        case .member(let tab): tab
        case .placeholder: nil
        }
    }

    /// The slots a row of `members` lays out, with the drop column opened at
    /// `placeholderIndex` when a drag has resolved one.
    ///
    /// An index outside `0...members.count` is not a slot, so the row lays out
    /// as though no drag were in flight.
    static func slots(
        members: [BrowserTab],
        placeholderIndex: Int?
    ) -> [BrowserSplitColumnSlot] {
        var slots = members.map(BrowserSplitColumnSlot.member)
        guard let placeholderIndex,
            placeholderIndex >= 0,
            placeholderIndex <= members.count
        else { return slots }
        slots.insert(.placeholder, at: placeholderIndex)
        return slots
    }
}
