import SwiftUI

/// How a fill of two or three colors runs: along a line, out from the middle,
/// or around it. A fill of one color is that color whatever its kind. Every
/// kind blends its colors in a perceptual space, and two neighbors far apart
/// in hue turn around the wheel through the hues between them rather than
/// through gray.
///
/// The three instances below are the one table of what each kind draws.
struct CrestGradientKind: Hashable, Sendable, Identifiable {
    // MARK: - Static Variables

    /// The colors run from one edge to the other, at the fill's direction.
    static let linear = CrestGradientKind(
        name: "linear", title: "Linear", takesDirection: true, closesLoop: false,
        draws: { gradient, degrees in
            let unit = UnitPoint.along(degrees)
            return AnyShapeStyle(LinearGradient.linearGradient(gradient, startPoint: unit.opposite, endPoint: unit))
        })

    /// The first color sits in the middle, and the others ring out from it.
    static let radial = CrestGradientKind(
        name: "radial", title: "Radial", takesDirection: false, closesLoop: false,
        draws: { gradient, _ in
            AnyShapeStyle(EllipticalGradient.ellipticalGradient(gradient, center: .center))
        })

    /// The colors turn around the middle, starting at the fill's direction,
    /// and come back to the first.
    static let angular = CrestGradientKind(
        name: "angular", title: "Angular", takesDirection: true, closesLoop: true,
        draws: { gradient, degrees in
            AnyShapeStyle(AngularGradient.conicGradient(gradient, center: .center, angle: .degrees(degrees)))
        })

    static let all = [linear, radial, angular]

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource
    /// Whether the kind runs in a direction the person can turn.
    let takesDirection: Bool
    /// Whether the colors come back around to the first.
    let closesLoop: Bool
    var id: String { name }
    private let draws: @Sendable (AnyGradient, Double) -> AnyShapeStyle

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, takesDirection: Bool, closesLoop: Bool,
        draws: @escaping @Sendable (AnyGradient, Double) -> AnyShapeStyle
    ) {
        self.name = name
        self.title = title
        self.takesDirection = takesDirection
        self.closesLoop = closesLoop
        self.draws = draws
    }

    // MARK: - Initializers (stored)

    /// The kind a Space's branding stores, where none is linear.
    init(_ stored: SpaceGradientKind?) {
        self = Self.named(stored?.name) ?? .linear
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> CrestGradientKind? {
        all.first { $0.name == name }
    }

    /// The kind as a Space's branding stores it, where linear is none.
    var stored: SpaceGradientKind? {
        SpaceGradientKind.all.first { $0.name == name && $0.name != CrestGradientKind.linear.name }
    }

    // MARK: - Actions - Drawing

    /// `colors` drawn as this kind, running toward `degrees`: 0 runs left to
    /// right and 90 top to bottom, as a Space's gradient angle does. One color
    /// draws as itself.
    func style(of colors: [BrandColor], toward degrees: Double) -> AnyShapeStyle {
        guard colors.count > 1 else { return AnyShapeStyle((colors.first ?? .indigo).color) }
        let stops = CrestPerceptualColor.blendingStops(closesLoop ? colors + colors.prefix(1) : colors)
        let gradient = Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color, location: $0.location) })
        return draws(gradient.colorSpace(.perceptual), degrees)
    }
}

// MARK: - Hashable

extension CrestGradientKind {
    static func == (lhs: CrestGradientKind, rhs: CrestGradientKind) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension UnitPoint {
    /// The point on the unit square's edge that `degrees` points to from its
    /// middle: 0 points right and 90 down.
    fileprivate static func along(_ degrees: Double) -> UnitPoint {
        let radians = degrees * .pi / 180
        return UnitPoint(x: 0.5 + 0.5 * cos(radians), y: 0.5 + 0.5 * sin(radians))
    }

    /// The point across the middle from this one.
    fileprivate var opposite: UnitPoint {
        UnitPoint(x: 1 - x, y: 1 - y)
    }
}
