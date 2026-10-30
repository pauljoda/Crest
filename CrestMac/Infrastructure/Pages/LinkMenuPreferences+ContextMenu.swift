import Foundation

/// How the link menu preferences arrange Crest's rows in a page's context
/// menu, and the edits the Links settings make to them, each a whole new
/// record the core then keeps.
extension LinkMenuPreferences {
    // MARK: - Actions - Menu

    /// `actions` in the order of their rows, leaving out the rows a person
    /// hid. Actions of one row keep their own order.
    @MainActor func arranging(_ actions: [BrowserPageContextMenuAction]) -> [BrowserPageContextMenuAction] {
        rows.filter(\.isShown).flatMap { choice in actions.filter { $0.row == choice.row } }
    }

    /// Whether the menu shows `row`.
    func shows(_ row: LinkMenuRow) -> Bool {
        rows.first { $0.row == row }?.isShown ?? true
    }

    // MARK: - Mutators

    /// These preferences with `row` shown or hidden.
    func showing(_ row: LinkMenuRow, _ isShown: Bool) -> LinkMenuPreferences {
        var edited = self
        edited.rows = rows.map { $0.row == row ? LinkMenuChoice(row: row, isShown: isShown) : $0 }
        return edited
    }

    /// These preferences with the rows at `offsets` moved before `destination`.
    func moving(from offsets: IndexSet, to destination: Int) -> LinkMenuPreferences {
        var edited = self
        edited.rows.move(fromOffsets: offsets, toOffset: destination)
        return edited
    }

    /// These preferences with `row` moved to where `target` stands, as a drag
    /// over `target` moves it.
    func moving(_ row: LinkMenuRow, to target: LinkMenuRow) -> LinkMenuPreferences {
        let order = rows.map(\.row)
        guard let from = order.firstIndex(of: row), let to = order.firstIndex(of: target), from != to else {
            return self
        }
        return moving(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
    }
}
