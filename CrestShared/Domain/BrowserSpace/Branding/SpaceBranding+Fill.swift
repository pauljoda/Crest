import Foundation

/// A Space's colors as the color well picks them and the sidebar, crest and
/// icon draw them: each one color, or a gradient of its kind toward its
/// angle. A Space is two wells, Background and Accent, the palette's first
/// two colors, each running on into the further colors its own gradient
/// keeps, which builds before gradients ignore, drawing the first. Its third
/// color, Pattern, is a shade of Background until a sidebar pattern shows it.
/// A Space from before the wells may draw its colors as one gradient, or give
/// its icon a color of its own.
extension SpaceBranding {
    // MARK: - Static Variables

    /// A slot's gradient that adds no color.
    static let plainGradient = BrandGradient(colors: ColorPalette(colors: []), kind: nil, angle: 0)

    // MARK: - Variables

    /// The sidebar's color: the Space's colors, as its gradient runs.
    var sidebarFill: CrestColorFill {
        get { CrestColorFill(colors.colors, kind: CrestGradientKind(gradientKind), degrees: gradientAngle) }
        set {
            colors = ColorPalette(colors: newValue.colors)
            gradientKind = newValue.kind.stored
            gradientAngle = newValue.degrees
            hasCustomAppearance = true
        }
    }

    /// The Space's Background, which the sidebar wears. Setting it gives a
    /// Space that drew its colors as one gradient its wells, and a sidebar
    /// with no pattern a Pattern shaded from it.
    var backgroundFill: CrestColorFill {
        get { themeMode == .gradient ? sidebarFill : slotFill(0) }
        set {
            let accent = accentFill
            if themeMode == .gradient {
                themeMode = .banner
                bannerPattern = .solid
                colorGradients = nil
            }
            setSlotFill(newValue, at: 0)
            setSlotFill(accent, at: 1)
            if bannerPattern == .solid { setSlotFill(newValue.shaded, at: 2) }
        }
    }

    /// The Space's Accent: the color its crest's emblem and border, its icon
    /// and its highlights wear. An icon given a color of its own before the
    /// wells keeps wearing it until the Accent is set, which it then follows.
    var accentFill: CrestColorFill {
        get { symbolColor.map { Self.fill($0, into: symbolGradient) } ?? slotFill(1) }
        set {
            symbolColor = nil
            symbolGradient = nil
            setSlotFill(newValue, at: 1)
        }
    }

    /// The Space's Pattern, which a sidebar pattern and a crest's field wear.
    var patternFill: CrestColorFill {
        get { slotFill(2) }
        set { setSlotFill(newValue, at: 2) }
    }

    /// Whether the sidebar draws a pattern, which shows the Pattern color.
    var showsPattern: Bool { themeMode == .banner && bannerPattern != .solid }

    // MARK: - Functions

    /// The well of `role`: the Space's Background, Accent or Pattern.
    func wellFill(_ role: BrowserSpaceBrandColorRole) -> CrestColorFill {
        role == .background ? backgroundFill : (role == .accent ? accentFill : patternFill)
    }

    /// The palette's color at `slot`, with the gradient it runs into.
    func slotFill(_ slot: Int) -> CrestColorFill {
        let base =
            colors.colors.indices.contains(slot) ? colors.colors[slot] : (colors.colors.last ?? Self.fallbackColor)
        let gradients = colorGradients?.slots ?? []
        return Self.fill(base, into: gradients.indices.contains(slot) ? gradients[slot] : nil)
    }

    /// The fill a crest layer drawn from palette entry `index` wears, with
    /// the gradient that entry runs into: the crest's own palette's when it
    /// keeps one, or else the Space's.
    func crestLayerFill(_ index: Int) -> CrestColorFill {
        guard let palette = crest.palette?.colors, !palette.isEmpty else { return slotFill(index) }
        let base = palette.indices.contains(index) ? palette[index] : palette[0]
        let gradients = crest.paletteGradients?.slots ?? []
        return Self.fill(base, into: gradients.indices.contains(index) ? gradients[index] : nil)
    }

    // MARK: - Mutators

    /// Sets the well of `role`, as its well does.
    mutating func setWellFill(_ fill: CrestColorFill, of role: BrowserSpaceBrandColorRole) {
        if role == .background {
            backgroundFill = fill
        } else if role == .accent {
            accentFill = fill
        } else {
            patternFill = fill
        }
    }

    /// Draws `pattern` on the sidebar, in the Space's wells. The solid
    /// sidebar takes its Pattern back as a shade of its Background.
    mutating func wearPattern(_ pattern: SpaceBannerPattern) {
        if themeMode == .gradient { backgroundFill = backgroundFill }
        bannerPattern = pattern
        if pattern == .solid { patternFill = backgroundFill.shaded }
        hasCustomAppearance = true
    }

    /// Gives the palette's color at `slot` the fill, giving the palette every
    /// color up to that one.
    mutating func setSlotFill(_ fill: CrestColorFill, at slot: Int) {
        guard let color = fill.colors.first else { return }
        while colors.count <= slot { colors.append(colors.last ?? color) }
        colors[slot] = color
        colorGradients = Self.gradients(colorGradients, setting: fill, at: slot)
        hasCustomAppearance = true
    }

    // MARK: - Actions - Gradients

    /// `base` running into `gradient`'s colors, or plain without one.
    static func fill(_ base: BrandColor, into gradient: BrandGradient?) -> CrestColorFill {
        guard let gradient, !gradient.colors.colors.isEmpty else { return CrestColorFill(base) }
        return CrestColorFill(
            [base] + gradient.colors.colors, kind: CrestGradientKind(gradient.kind), degrees: gradient.angle)
    }

    /// `gradients` with the gradient `fill` makes at `slot`, or nil when every
    /// slot is plain.
    static func gradients(_ gradients: PaletteGradients?, setting fill: CrestColorFill, at slot: Int)
        -> PaletteGradients?
    {
        var slots = gradients?.slots ?? []
        while slots.count <= slot { slots.append(plainGradient) }
        slots[slot] = gradient(after: fill) ?? plainGradient
        return slots.allSatisfy { $0.colors.colors.isEmpty } ? nil : PaletteGradients(slots: slots)
    }

    /// The gradient `fill`'s colors after its first make, or nil for one color.
    static func gradient(after fill: CrestColorFill) -> BrandGradient? {
        guard fill.isGradient else { return nil }
        return BrandGradient(
            colors: ColorPalette(colors: Array(fill.colors.dropFirst())), kind: fill.kind.stored, angle: fill.degrees)
    }
}
