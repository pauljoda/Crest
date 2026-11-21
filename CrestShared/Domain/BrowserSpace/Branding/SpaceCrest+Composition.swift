import Foundation

/// A crest's composition as the Studio edits and the renderer draws it: the
/// colors and figure the layers use.
extension SpaceCrest {
    // MARK: - Static Variables

    // MARK: - Variables

    /// The figure this crest draws: a custom charge when one was chosen, else
    /// the heraldic symbol.
    var resolvedCharge: CrestCharge {
        charge ?? .heraldic(symbol)
    }

    // MARK: - Actions - Colors

    /// The colors this crest's layer indices point into.
    func layerColors(spaceColors: ColorPalette) -> ColorPalette {
        if let palette, !palette.isEmpty { return palette }
        return spaceColors.isEmpty ? [.indigo] : spaceColors
    }
}

extension CrestMeasure {
    /// The range the renderer draws the measure in.
    var range: ClosedRange<Double> { minimum...maximum }

}
