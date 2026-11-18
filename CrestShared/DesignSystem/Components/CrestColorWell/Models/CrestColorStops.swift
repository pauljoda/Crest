import Foundation

/// The colors of a fill being edited, each with an identity of its own while
/// it stays, and which of them Crest placed and the person has not moved.
/// A color Crest adds goes where `CrestColorHarmony` puts it: a second beside
/// the first, and a third that carries on the run when the second is still
/// Crest's, or carries on the person's two when they placed both. Every color
/// moves on its own unless the colors are linked, when moving one orbits the
/// rest with it round the wheel, keeping the gradient's shape; adding a color
/// moves none the person placed, and one the person moves becomes theirs.
struct CrestColorStops {
    // MARK: - Variables

    /// The indices of the colors Crest placed.
    private(set) var placed: Set<Int> = []
    private var identities: [UUID] = []
    /// The colors as they stood on the wheel when linked moves began, which
    /// every linked move turns and scales as a whole, so the rest orbit with
    /// the moved color and never drift. Changing the colors any other way
    /// lets it go.
    private var shape: [CrestColorWheelPoint]?

    // MARK: - Functions

    /// Each of `fill`'s colors' identity, in order. A fill that changed
    /// count elsewhere gets identities by place until `adopt(_:)` gives it
    /// its own.
    func ids(of fill: CrestColorFill) -> [UUID] {
        guard identities.count != fill.colors.count else { return identities }
        return fill.colors.indices.map { index in
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index)))
        }
    }

    // MARK: - Mutators

    /// Takes `fill` as the person's own, giving each color an identity, when
    /// it holds a different number of colors than the stops follow.
    mutating func adopt(_ fill: CrestColorFill) {
        guard identities.count != fill.colors.count else { return }
        identities = fill.colors.map { _ in UUID() }
        placed = []
    }

    /// Adds a color to `fill` where harmony puts it. A second color follows
    /// the first. A third carries on Crest's run when the second is still
    /// Crest's, putting it back where the first now wants it, or carries on
    /// the person's two colors when they placed both.
    mutating func add(to fill: inout CrestColorFill) {
        guard fill.canAddColor, let first = fill.colors.first else { return }
        adopt(fill)
        shape = nil
        if fill.colors.count == 1 {
            fill.add(CrestColorHarmony.run(beside: first)[0])
        } else if placed.contains(1) {
            let run = CrestColorHarmony.run(beside: first)
            fill.set(run[0], at: 1)
            fill.add(run[1])
        } else {
            fill.add(CrestColorHarmony.third(after: first, fill.colors[1]))
        }
        identities.append(UUID())
        placed.insert(fill.colors.count - 1)
    }

    /// Takes the color at `index` out of `fill`, leaving the rest where they
    /// are.
    mutating func remove(at index: Int, from fill: inout CrestColorFill) {
        guard fill.canRemoveColor, fill.colors.indices.contains(index) else { return }
        adopt(fill)
        shape = nil
        fill.remove(at: index)
        identities.remove(at: index)
        placed = Set(placed.compactMap { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) })
    }

    /// Moves the color at `index` to the person's `color`, which makes it
    /// theirs. Linked, the rest orbit with it as the gradient stood when
    /// linked moves began: turned round the wheel's center by the same angle,
    /// drawn in or out in proportion, and lightened or darkened by the same
    /// step, never past the rim. Unlinked, no other color moves.
    mutating func move(_ color: BrandColor, at index: Int, in fill: inout CrestColorFill, linked: Bool) {
        guard linked, fill.isGradient, fill.colors.indices.contains(index) else {
            set(color, at: index, in: &fill)
            return
        }
        adopt(fill)
        if shape?.count != fill.colors.count { shape = fill.colors.map(CrestColorWheelPoint.init) }
        guard let shape else { return }
        let from = shape[index]
        let to = CrestColorWheelPoint(color)
        let room = CrestColorStopsMetrics.vibrancyRoom
        let reach = (to.vibrancy + room) / (from.vibrancy + room)
        for (position, stop) in shape.enumerated() where position != index {
            let orbited = CrestColorWheelPoint(
                hue: stop.hue + to.hue - from.hue,
                vibrancy: (stop.vibrancy + room) * reach - room,
                lightness: stop.lightness + to.lightness - from.lightness)
            fill.set(orbited.color, at: position)
        }
        fill.set(color, at: index)
        placed.remove(index)
    }

    /// Lets the linked shape go, so the next linked move starts from the
    /// colors as they are then.
    mutating func releaseShape() {
        shape = nil
    }

    /// Sets the color at `index` to the person's `color`, which makes it
    /// theirs. No other color moves.
    mutating func set(_ color: BrandColor, at index: Int, in fill: inout CrestColorFill) {
        shape = nil
        fill.set(color, at: index)
        placed.remove(index)
    }
}

enum CrestColorStopsMetrics {
    /// The vibrancy added to both sides of a linked move's reach, so a moved
    /// color at the wheel's center still carries the others in and out
    /// smoothly rather than multiplying their distance by nothing.
    static let vibrancyRoom = 0.02
}
