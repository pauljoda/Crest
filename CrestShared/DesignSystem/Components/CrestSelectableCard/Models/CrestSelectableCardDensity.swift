import CoreGraphics

/// How much room a selectable card takes: a card of its own with a checkmark,
/// a tile in a grid or a chip in a row, or the ring around a color swatch.
/// Every density draws the same selection, hover, press and focus.
struct CrestSelectableCardDensity: Hashable, Sendable {
    // MARK: - Static Variables

    /// A card of its own, with room for a title and a line of detail.
    static let regular = CrestSelectableCardDensity(
        name: "regular",
        cornerRadius: CrestRadius.card,
        padding: CrestSpacing.large,
        fillsWidth: true,
        showsCheckmark: true,
        showsRestingFill: true,
        restingBorderWidth: CrestLayout.hairline
    )
    /// A tile in a grid of choices, or a chip in a row of them.
    static let compact = CrestSelectableCardDensity(
        name: "compact",
        cornerRadius: CrestRadius.control,
        padding: CrestSpacing.small,
        fillsWidth: true,
        showsCheckmark: false,
        showsRestingFill: true,
        restingBorderWidth: 0
    )
    /// A ring around a color swatch, drawn once the pointer is over it or the
    /// color is chosen.
    static let swatch = CrestSelectableCardDensity(
        name: "swatch",
        cornerRadius: nil,
        padding: CrestSpacing.extraSmall,
        fillsWidth: false,
        showsCheckmark: false,
        showsRestingFill: false,
        restingBorderWidth: 0
    )

    // MARK: - Variables

    let name: String
    /// The corner radius of the card's outline, or nil for a circle.
    let cornerRadius: CGFloat?
    /// The room between the card's edge and its content.
    let padding: CGFloat
    /// Whether the card stretches across the width it is offered.
    let fillsWidth: Bool
    /// Whether a checkmark beside the content marks the chosen card.
    let showsCheckmark: Bool
    /// Whether the card draws its quiet surface before it is hovered or chosen.
    let showsRestingFill: Bool
    /// The border before the card is chosen. Increase Contrast always draws one.
    let restingBorderWidth: CGFloat

    // MARK: - Initializers

    private init(
        name: String,
        cornerRadius: CGFloat?,
        padding: CGFloat,
        fillsWidth: Bool,
        showsCheckmark: Bool,
        showsRestingFill: Bool,
        restingBorderWidth: CGFloat
    ) {
        self.name = name
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.fillsWidth = fillsWidth
        self.showsCheckmark = showsCheckmark
        self.showsRestingFill = showsRestingFill
        self.restingBorderWidth = restingBorderWidth
    }

    // MARK: - Actions - Identity

    static func == (lhs: CrestSelectableCardDensity, rhs: CrestSelectableCardDensity) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
