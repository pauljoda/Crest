import Foundation

extension PalettePreferences {
    // MARK: - Actions - Sources

    /// Whether the palette offers results of `source`.
    func offers(_ source: PaletteSource) -> Bool {
        sources.first { $0.source == source }?.isEnabled ?? false
    }
}
