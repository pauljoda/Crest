import Foundation

/// One hold of a Most Recent Tab shortcut, from the first press to the
/// release, as pure state: which item is highlighted, whether the panel shows
/// yet, and what each key, release or change of the list does. The shell turns
/// events into these calls and acts on what they answer.
struct RecentTabSwitcherSession: Equatable {
    // MARK: - Static Variables

    /// How many items the switcher lists, and the most 1-5 can reach.
    static let maximumItems = 5

    // MARK: - Types

    /// What a key means while the switcher is held.
    enum Key: Equatable {
        case move(RecentTabSwitchDirection)
        case highlight(index: Int)
        case commit
        case close
        case cancel
        case other
    }

    /// How the session ends.
    enum Outcome: Equatable {
        case commit(RecentTabItem)
        case cancel
    }

    /// What a key or release did: whether the switcher took the key from the
    /// page, and the end of the session when it was one.
    struct Response: Equatable {
        // MARK: - Variables

        let isConsumed: Bool
        let outcome: Outcome?
        let itemToClose: RecentTabItem?

        // MARK: - Initializers

        init(isConsumed: Bool, outcome: Outcome? = nil, itemToClose: RecentTabItem? = nil) {
            self.isConsumed = isConsumed
            self.outcome = outcome
            self.itemToClose = itemToClose
        }
    }

    // MARK: - Variables

    private(set) var items: [RecentTabItem]
    private(set) var pendingCloseItem: RecentTabItem?
    private var releasedWhileClosing = false
    private let originalItem: RecentTabItem?
    private(set) var highlightedIndex: Int
    private(set) var isShowing = false
    /// The modifiers whose release ends the hold: the binding's, but Shift.
    let heldModifiers: ShortcutModifiers
    private let bindings: [BrowserShortcutKey: RecentTabSwitchDirection]
    private let specialKeys: [ShortcutSpecialKey: Key]

    /// The panel needs at least one remaining item.
    var presentsPanel: Bool { isShowing && !items.isEmpty && !releasedWhileClosing }

    /// The item a release commits now.
    var highlightedItem: RecentTabItem? {
        items.indices.contains(highlightedIndex) ? items[highlightedIndex] : nil
    }

    // MARK: - Initializers

    /// A hold begun by `direction`'s command bound to `binding`, over `items`,
    /// with `otherBinding` for the command that goes the other way, in a
    /// layout that runs right to left when `rightToLeft`. Nil when the binding
    /// has no modifier to hold.
    init?(
        direction: RecentTabSwitchDirection, binding: BrowserShortcut, otherBinding: BrowserShortcut?,
        items: [RecentTabItem], rightToLeft: Bool = false
    ) {
        let held = binding.modifiers.subtracting(.shift)
        guard !held.isEmpty else { return nil }
        heldModifiers = held
        self.items = Array(items.prefix(Self.maximumItems))
        originalItem = self.items.first
        highlightedIndex = direction.startingIndex(count: min(items.count, Self.maximumItems))
        // A key's own direction is the one it has without Shift, which
        // reverses it: Control-Shift-Tab is Tab's backward.
        var bindings: [BrowserShortcutKey: RecentTabSwitchDirection] = [.special(.tab): .forward]
        if let otherBinding {
            bindings[otherBinding.key] = otherBinding.modifiers.contains(.shift) ? direction : direction.reversed
        }
        bindings[binding.key] = binding.modifiers.contains(.shift) ? direction.reversed : direction
        self.bindings = bindings
        specialKeys = Self.specialKeys(rightToLeft: rightToLeft)
    }

    // MARK: - Actions - Input

    /// A key pressed while held. The shortcut carries the key and the
    /// modifiers down with it; Shift turns a move around.
    mutating func keyDown(_ shortcut: BrowserShortcut, isRepeat: Bool = false) -> Response {
        // A press without the held modifiers means the release never arrived.
        guard shortcut.modifiers.isSuperset(of: heldModifiers) else {
            return Response(isConsumed: false, outcome: modifiersChanged(to: shortcut.modifiers))
        }
        if pendingCloseItem != nil {
            return Response(isConsumed: true, outcome: key(for: shortcut) == .cancel ? .cancel : nil)
        }
        switch key(for: shortcut) {
        case .move(let direction):
            isShowing = true
            highlightedIndex = direction.index(from: highlightedIndex, count: items.count)
            return Response(isConsumed: true, outcome: nil)
        case .highlight(let index):
            isShowing = true
            if items.indices.contains(index) { highlightedIndex = index }
            return Response(isConsumed: true, outcome: nil)
        case .commit:
            return Response(isConsumed: true, outcome: finish())
        case .close:
            guard !isRepeat else { return Response(isConsumed: true) }
            pendingCloseItem = highlightedItem
            return Response(isConsumed: true, itemToClose: highlightedItem)
        case .cancel:
            return Response(isConsumed: true, outcome: .cancel)
        case .other:
            // Nothing reaches the page while the panel is up.
            return Response(isConsumed: isShowing, outcome: nil)
        }
    }

    /// The modifiers held now. A release of any held one ends the hold.
    mutating func modifiersChanged(to modifiers: ShortcutModifiers) -> Outcome? {
        guard !modifiers.isSuperset(of: heldModifiers) else { return nil }
        if pendingCloseItem != nil {
            releasedWhileClosing = true
            return nil
        }
        return finish()
    }

    /// The moment the panel is due, with the modifiers held then, which end
    /// the hold when a release went unseen.
    mutating func showDelayElapsed(modifiers: ShortcutModifiers) -> Outcome? {
        guard modifiers.isSuperset(of: heldModifiers) else { return finish() }
        isShowing = true
        return nil
    }

    /// Points the highlight at `index`, as the pointer does.
    mutating func highlight(index: Int) {
        guard pendingCloseItem == nil, items.indices.contains(index) else { return }
        highlightedIndex = index
    }

    /// Reconciles external changes without reordering or refilling the held
    /// list. Closed durable tabs and split companions stay out of this hold.
    mutating func refresh(items newItems: [RecentTabItem]) -> Outcome? {
        guard pendingCloseItem == nil else { return nil }
        let highlighted = highlightedItem
        var retained: [RecentTabItem] = []
        for item in items {
            guard let updated = newItems.first(where: { !Set($0.tabIDs).isDisjoint(with: item.tabIDs) }),
                !retained.contains(where: { !Set($0.tabIDs).isDisjoint(with: updated.tabIDs) })
            else { continue }
            retained.append(updated)
        }
        items = retained
        let kept = highlighted.flatMap { highlighted in
            items.firstIndex { !Set($0.tabIDs).isDisjoint(with: highlighted.tabIDs) }
        }
        highlightedIndex = kept ?? min(highlightedIndex, max(items.count - 1, 0))
        return items.isEmpty ? .cancel : nil
    }

    /// Removes an approved close. Its right-hand neighbor takes the same
    /// index, or the last remaining item when the rightmost one was closed.
    mutating func closeCompleted(_ item: RecentTabItem, succeeded: Bool) -> Outcome? {
        guard pendingCloseItem == item else { return nil }
        pendingCloseItem = nil
        guard succeeded else { return releasedWhileClosing ? .cancel : nil }
        guard let index = items.firstIndex(of: item) else { return nil }
        items.remove(at: index)
        if index < highlightedIndex { highlightedIndex -= 1 }
        highlightedIndex = min(highlightedIndex, max(items.count - 1, 0))
        if items.isEmpty { return .cancel }
        return releasedWhileClosing ? finish() : nil
    }

    // MARK: - Actions - Ending

    /// Completing the hold selects the surviving highlight. Closes have
    /// already happened and are not undone by Escape or losing focus.
    func finish() -> Outcome {
        guard pendingCloseItem == nil, let item = highlightedItem, item != originalItem else { return .cancel }
        return .commit(item)
    }

    // MARK: - Actions - Keys

    /// The keys that move, choose or cancel. Left and Right follow the cards,
    /// which run the other way in a right-to-left layout.
    private static func specialKeys(rightToLeft: Bool) -> [ShortcutSpecialKey: Key] {
        [
            .leftArrow: .move(rightToLeft ? .forward : .backward), .upArrow: .move(.backward),
            .rightArrow: .move(rightToLeft ? .backward : .forward), .downArrow: .move(.forward),
            .returnKey: .commit, .escape: .cancel,
        ]
    }

    private func key(for shortcut: BrowserShortcut) -> Key {
        if isShowing, heldModifiers == .control,
            shortcut == BrowserShortcut(key: .character("w"), modifiers: .control)
        {
            return .close
        }
        if let direction = bindings[shortcut.key] {
            return .move(shortcut.modifiers.contains(.shift) ? direction.reversed : direction)
        }
        switch shortcut.key {
        case .special(let special): return specialKeys[special] ?? .other
        case .character(let character):
            guard let number = character.wholeNumberValue, (1...Self.maximumItems).contains(number) else {
                return .other
            }
            return .highlight(index: number - 1)
        }
    }

}
