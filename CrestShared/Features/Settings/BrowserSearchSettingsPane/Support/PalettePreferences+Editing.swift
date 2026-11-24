import Foundation

/// The edits the Search settings make to the palette preferences, each a
/// whole new record the core answers and then keeps. The core's rules order
/// the sections, keep each kind's own number of rows, and restore the default
/// order.
extension PalettePreferences {
    // MARK: - Static Variables

    /// The numbers of rows a section may be set to show.
    static let limits = offeredLimits

    // MARK: - Variables

    /// The kinds the person places among the sections, in their order.
    var sections: [PaletteSourceChoice] { sources.filter { $0.source.isArranged } }

    /// The kinds that join a section or lead the list, in catalog order.
    var extras: [PaletteSourceChoice] { sources.filter { !$0.source.isSection } }

    // MARK: - Actions - Reading

    /// The most rows `source` shows: the person's number, else the kind's own.
    func limit(of source: PaletteSource) -> Int {
        sources.first { $0.source == source }?.limit ?? source.defaultLimit
    }

    // MARK: - Actions - Editing

    /// These preferences with `source` offered or not.
    func offering(_ source: PaletteSource, _ isEnabled: Bool) -> PalettePreferences {
        edited(PaletteOffering(preferences: self, source: source, isEnabled: isEnabled))
    }

    /// These preferences with `source` showing at most `limit` rows, or its
    /// own number when `limit` is that number.
    func limiting(_ source: PaletteSource, to limit: Int) -> PalettePreferences {
        edited(PaletteLimiting(preferences: self, source: source, limit: limit))
    }

    /// These preferences with the sections at `offsets` moved before
    /// `destination`, both counted among the sections alone, as a list drag
    /// moves them.
    func movingSections(from offsets: IndexSet, to destination: Int) -> PalettePreferences {
        guard let from = offsets.first, offsets.count == 1, sections.indices.contains(from) else { return self }
        return edited(
            PaletteSectionMove(
                preferences: self, source: sections[from].source,
                index: from < destination ? destination - 1 : destination))
    }

    /// These preferences with the section `source` moved to where `target`
    /// stands among the sections, as a drag over `target` moves it.
    func moving(_ source: PaletteSource, to target: PaletteSource) -> PalettePreferences {
        guard let to = sections.firstIndex(where: { $0.source == target }) else { return self }
        return edited(PaletteSectionMove(preferences: self, source: source, index: to))
    }

    /// These preferences with the sections in their default order, each kept
    /// on or off as the person set it.
    func restoringSectionOrder() -> PalettePreferences {
        edited(PaletteSectionOrder(preferences: self))
    }

    /// The preferences the core answers for `edit`, or these unchanged when it
    /// cannot answer.
    private func edited<Edit: Query>(_ edit: Edit) -> PalettePreferences where Edit.Answer == PalettePreferences {
        (try? CrestCore.answer(edit)) ?? self
    }
}
