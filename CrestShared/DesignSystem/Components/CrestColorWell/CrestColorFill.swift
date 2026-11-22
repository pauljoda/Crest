import SwiftUI

/// A color as a person picks it in Crest: one color, or a gradient of two or
/// three that runs as `kind` toward `degrees`. Anything SwiftUI fills, strokes
/// or tints can wear it.
struct CrestColorFill: Equatable, Sendable {
    // MARK: - Static Variables

    /// The most colors a gradient holds.
    static let maximumColors = 3

    // MARK: - Variables

    /// The colors in order, from one to `maximumColors`.
    private(set) var colors: [BrandColor]
    var kind: CrestGradientKind
    /// Where a linear or angular gradient runs: 0 left to right, 90 top to
    /// bottom, as a Space's gradient angle does.
    var degrees: Double

    /// Whether the fill is a gradient rather than one color.
    var isGradient: Bool { colors.count > 1 }
    var canAddColor: Bool { colors.count < Self.maximumColors }
    var canRemoveColor: Bool { colors.count > 1 }

    /// The fill as SwiftUI draws it: its one color, or its gradient.
    var style: AnyShapeStyle {
        kind.style(of: colors, toward: degrees)
    }

    /// The fill a step off itself, each color shaded as the harmony shades
    /// it, running the same way.
    var shaded: CrestColorFill {
        CrestColorFill(colors.map(CrestColorHarmony.shade(of:)), kind: kind, degrees: degrees)
    }

    // MARK: - Initializers

    /// `colors` as a fill, keeping the first `maximumColors`. An empty list
    /// is the default neutral gray.
    init(_ colors: [BrandColor], kind: CrestGradientKind = .linear, degrees: Double = 90) {
        let kept = Array(colors.prefix(Self.maximumColors))
        self.colors = kept.isEmpty ? [BrandColor.folderDefault] : kept
        self.kind = kind
        self.degrees = degrees
    }

    init(_ color: BrandColor) {
        self.init([color])
    }

    // MARK: - Functions

    /// The fill `amount` of the way toward `other`: each fill sampled at as
    /// many evenly spaced points as the longer one holds, each pair mixed in
    /// OKLab, turning the shorter way round toward `other`'s angle.
    func blended(toward other: CrestColorFill, by amount: Double) -> CrestColorFill {
        let count = Swift.max(colors.count, other.colors.count)
        let mixed = (0..<count).map { index in
            CrestPerceptualColor.mix(color(at: index, of: count), other.color(at: index, of: count), by: amount)
        }
        let start = isGradient ? degrees : other.degrees
        let end = other.isGradient ? other.degrees : degrees
        var turn = (end - start).truncatingRemainder(dividingBy: 360)
        if turn > 180 { turn -= 360 } else if turn < -180 { turn += 360 }
        return CrestColorFill(mixed, kind: amount < 0.5 ? kind : other.kind, degrees: start + turn * amount)
    }

    /// The fill's color at point `index` of `count` evenly spaced along it.
    private func color(at index: Int, of count: Int) -> BrandColor {
        guard colors.count > 1, count > 1 else { return colors[0] }
        let position = Double(index) / Double(count - 1) * Double(colors.count - 1)
        let lower = Swift.min(Int(position), colors.count - 2)
        return CrestPerceptualColor.mix(colors[lower], colors[lower + 1], by: position - Double(lower))
    }

    // MARK: - Mutators

    /// Sets the color at `index`, when the fill holds one there.
    mutating func set(_ color: BrandColor, at index: Int) {
        guard colors.indices.contains(index) else { return }
        colors[index] = color
    }

    /// Adds `color` at the end, while the fill holds fewer than
    /// `maximumColors`.
    mutating func add(_ color: BrandColor) {
        guard canAddColor else { return }
        colors.append(color)
    }

    /// Takes out the color at `index`, keeping at least one.
    mutating func remove(at index: Int) {
        guard canRemoveColor, colors.indices.contains(index) else { return }
        colors.remove(at: index)
    }
}
