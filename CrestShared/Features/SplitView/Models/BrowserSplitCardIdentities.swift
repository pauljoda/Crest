import Foundation

/// Which card each member of a split row is drawn in, and whether the last
/// change to the members settles with the row's motion.
///
/// A card keeps its member's tab for the life of the row, so a tab joining,
/// leaving or moving leaves the other cards, and the live pages in them, where
/// they are, and they resize into place. A lone card is the one exception:
/// showing another tab alone swaps the page inside the same card, and so the
/// same host, as a tab switch outside a split always has, rather than building
/// a new card and fading it in over the old one.
///
/// Telling the two apart needs the members the row drew last, which is why
/// this is a reference the row keeps rather than a value it derives.
@MainActor
final class BrowserSplitCardIdentities {
    // MARK: - Variables

    /// The card each member was last drawn in, by tab.
    private var cards: [UUID: UUID] = [:]
    private var lastMembers: [UUID] = []
    /// Whether the last change to the members settles with the row's motion:
    /// a card joining, leaving or moving does, and a tab switch lands at once.
    private(set) var settles = true

    // MARK: - Actions - Identity

    /// The card each of `members` is drawn in, by tab, carried over from the
    /// row drawn last.
    func cards(for members: [UUID]) -> [UUID: UUID] {
        guard members != lastMembers else { return cards }
        var next: [UUID: UUID] = [:]
        for member in members {
            next[member] = cards[member]
        }
        // Another tab shown alone takes over the lone card.
        if members.count == 1, lastMembers.count == 1, next.isEmpty, let card = cards.values.first {
            next[members[0]] = card
        }
        var taken = Set(next.values)
        for member in members where next[member] == nil {
            // A tab arriving whose own identity a lone card already wears
            // takes a new one, so no two cards share an identity.
            let card = taken.contains(member) ? UUID() : member
            next[member] = card
            taken.insert(card)
        }
        settles = Self.settles(from: lastMembers, to: members)
        cards = next
        lastMembers = members
        return next
    }

    /// Whether going from `old` to `new` settles with the row's motion. A row
    /// that shows a lone page on either side of the change and shares no tab
    /// across it has switched tabs, which lands at once, as it does outside a
    /// split; every other change moves cards that stay.
    private static func settles(from old: [UUID], to new: [UUID]) -> Bool {
        guard old.count == 1 || new.count == 1 else { return true }
        return !Set(old).isDisjoint(with: new)
    }
}
