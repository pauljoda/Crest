import SwiftUI

/// One Space as the switcher draws it when Space icons are dots: in the
/// sidebar's own text color, brightest for the Space shown, lighter for the
/// others in its group, and dark for the rest. A locked Space is a ring. In
/// the switcher the shades follow the pager from one Space to the next.
struct BrowserSpaceDot: View {
    // MARK: - Types

    /// How strongly a dot wears the sidebar's text color.
    struct Shade: Hashable, Sendable {
        /// The Space shown.
        static let shown = Shade(opacity: 1)
        /// Another Space in the shown Space's group.
        static let grouped = Shade(opacity: 0.45)
        /// Every other Space.
        static let other = Shade(opacity: 0.18)

        let opacity: Double
    }

    /// The Spaces a switcher's dots are shaded among: each Space's profile,
    /// which a group's Spaces share and no two groups do, and the Space shown
    /// while the pager is still.
    struct Field: Equatable, Sendable {
        let profiles: [UUID: UUID]
        let selectedSpaceID: UUID

        /// How strongly `spaceID`'s dot wears the text color with the pager at
        /// `progress`: the shades of the two Spaces it stands between, blended
        /// by how far along it is.
        func opacity(of spaceID: UUID, at progress: SpacePagerProgress?) -> Double {
            var from = selectedSpaceID
            var to = selectedSpaceID
            var fraction = 0.0
            if let progress,
                let sample = SpacePagerInterpolation(position: progress.position, count: progress.order.count)
            {
                from = progress.order[sample.lower]
                to = progress.order[sample.upper]
                fraction = Double(sample.fraction)
            }
            let shown = (spaceID == from ? 1 - fraction : 0) + (spaceID == to ? fraction : 0)
            let grouped = (sharesGroup(spaceID, from) ? 1 - fraction : 0) + (sharesGroup(spaceID, to) ? fraction : 0)
            return Shade.other.opacity + (Shade.grouped.opacity - Shade.other.opacity) * grouped
                + (Shade.shown.opacity - Shade.grouped.opacity) * shown
        }

        private func sharesGroup(_ spaceID: UUID, _ other: UUID) -> Bool {
            guard let profile = profiles[spaceID] else { return false }
            return profile == profiles[other]
        }
    }

    // MARK: - Static Variables

    static let diameter: CGFloat = 7
    static let ringWidth: CGFloat = 1.5

    // MARK: - Variables

    private let shade: Shade?
    private let spaceID: UUID?
    private let field: Field?
    let isLocked: Bool
    var scale: CGFloat = 1

    @Environment(\.spaceChromeForeground) private var foreground
    @Environment(\.spacePagerProgress) private var progress

    // MARK: - Initializers

    /// A dot in one fixed shade, as a preview draws it.
    init(shade: Shade, isLocked: Bool, scale: CGFloat = 1) {
        self.shade = shade
        spaceID = nil
        field = nil
        self.isLocked = isLocked
        self.scale = scale
    }

    /// `spaceID`'s dot among `field`, shaded as the pager moves.
    init(spaceID: UUID, field: Field, isLocked: Bool, scale: CGFloat = 1) {
        shade = nil
        self.spaceID = spaceID
        self.field = field
        self.isLocked = isLocked
        self.scale = scale
    }

    // MARK: - Actions - Drawing

    var body: some View {
        let ink = (foreground ?? .primary).opacity(opacity)
        let diameter = Self.diameter * max(scale, 0.6)
        Circle()
            .strokeBorder(ink, lineWidth: isLocked ? Self.ringWidth : diameter / 2)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }

    private var opacity: Double {
        if let field, let spaceID { return field.opacity(of: spaceID, at: progress) }
        return (shade ?? .other).opacity
    }
}
