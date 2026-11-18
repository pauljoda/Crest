import SwiftUI

/// A part of the crest that wears a color of its own.
struct BrowserCrestForgeLayer: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let field = BrowserCrestForgeLayer(
        slot: 0, title: "Field", index: \.backplateColorIndex, role: .pattern, crestStep: .shape,
        crestHint: "Choose a shape to color its field", draws: { $0.backplate != .none })
    static let secondField = BrowserCrestForgeLayer(
        slot: 1, title: "Second field", index: \.secondaryFieldColorIndex, role: .background, crestStep: .field,
        crestHint: "Divide the field to use a second color",
        draws: { $0.backplate != .none && $0.fieldDivision != .plain })
    static let band = BrowserCrestForgeLayer(
        slot: 2, title: "Band", index: \.ordinaryColorIndex, role: .accent, crestStep: .band,
        crestHint: "Choose a band to color it", draws: { $0.backplate != .none && $0.ordinary != .none })
    static let emblem = BrowserCrestForgeLayer(
        slot: 3, title: "Emblem", index: \.symbolColorIndex, role: .accent, crestStep: .emblem,
        crestHint: "Choose an emblem to color it", draws: { $0.resolvedCharge.kind != .none }, isIconFigure: true)
    static let border = BrowserCrestForgeLayer(
        slot: 4, title: "Border", index: \.trimColorIndex, role: .accent, crestStep: .border,
        crestHint: "Choose a border to color it", draws: { $0.trim != .none })
    static let edge = BrowserCrestForgeLayer(
        slot: 5, title: "Edge", index: \.edgeColorIndex, role: .background, crestStep: .shape,
        crestHint: "Give the shape an edge to color it",
        draws: { $0.backplate != .none && ($0.edgeWidth > 0 || $0.showsOutline) })

    /// Every layer, in the order its swatches show and its palette entries sit.
    static let all: [BrowserCrestForgeLayer] = [field, secondField, band, emblem, border, edge]

    // MARK: - Variables

    /// The layer's entry in a crest palette with a color for each layer.
    let slot: Int
    let title: LocalizedStringResource

    /// The crest's index into its colors for this layer.
    let index: WritableKeyPath<SpaceCrest, Int> & Sendable
    /// The Space color the layer wears while the crest follows the Space:
    /// the field a shade off the sidebar, the emblem, band and border the
    /// Accent, and the second field and edge the Background.
    let role: BrowserSpaceBrandColorRole

    /// The step that gives a crest this layer, and what to do there, for a
    /// crest that doesn't draw it.
    let crestStep: BrowserCrestStudioStep
    let crestHint: LocalizedStringResource

    /// Whether a crest draws this layer.
    let draws: @Sendable (SpaceCrest) -> Bool

    /// Whether the layer is the figure an icon draws in place of a crest.
    let isIconFigure: Bool

    var id: Int { slot }

    // MARK: - Initializers

    private init(
        slot: Int, title: LocalizedStringResource, index: WritableKeyPath<SpaceCrest, Int> & Sendable,
        role: BrowserSpaceBrandColorRole, crestStep: BrowserCrestStudioStep, crestHint: LocalizedStringResource,
        draws: @escaping @Sendable (SpaceCrest) -> Bool, isIconFigure: Bool = false
    ) {
        self.slot = slot
        self.role = role
        self.title = title
        self.index = index
        self.crestStep = crestStep
        self.crestHint = crestHint
        self.draws = draws
        self.isIconFigure = isIconFigure
    }

    // MARK: - Actions - Drawing

    /// The layers whose colors `branding`'s stage shows: every layer of a
    /// crest, drawn or not, or an icon's one figure.
    static func shown(by branding: SpaceBranding) -> [BrowserCrestForgeLayer] {
        branding.iconStyle == .layeredCrest ? all : all.filter(\.isIconFigure)
    }

    /// The layer's name on `branding`'s stage: an icon's figure is its color.
    func title(in branding: SpaceBranding) -> LocalizedStringResource {
        branding.iconStyle == .layeredCrest || !isIconFigure ? title : "Color"
    }

    /// Whether `branding` draws this layer at all. An icon draws only its
    /// figure.
    func isDrawn(by branding: SpaceBranding) -> Bool {
        branding.iconStyle == .layeredCrest ? draws(branding.crest) : isIconFigure
    }

    /// The step that gives `branding` this layer: an icon becomes a crest
    /// under Emblem first.
    func enablingStep(for branding: SpaceBranding) -> BrowserCrestStudioStep {
        branding.iconStyle == .layeredCrest ? crestStep : .emblem
    }

    /// What to do to draw this layer in `branding`.
    func enablingHint(for branding: SpaceBranding) -> LocalizedStringResource {
        branding.iconStyle == .layeredCrest ? crestHint : "Choose Crest under Emblem to color the crest"
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCrestForgeLayer, rhs: BrowserCrestForgeLayer) -> Bool {
        lhs.slot == rhs.slot
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(slot)
    }
}

extension SpaceBranding {
    // MARK: - Crest layers

    /// Whether the crest wears the Space's colors, each layer its role's.
    var crestFollowsSpace: Bool {
        crest.palette == nil
            && BrowserCrestForgeLayer.all.allSatisfy { crest[keyPath: $0.index] == $0.role.slot }
    }

    /// Gives the crest the Space's colors back, each layer its role's.
    mutating func followSpaceColors() {
        crest.palette = nil
        crest.paletteGradients = nil
        for layer in BrowserCrestForgeLayer.all { crest[keyPath: layer.index] = layer.role.slot }
        hasCustomAppearance = true
    }

    /// Whether every layer already has a palette entry of its own.
    var hasLayeredCrestPalette: Bool {
        crest.palette?.count == BrowserCrestForgeLayer.all.count
            && BrowserCrestForgeLayer.all.allSatisfy { crest[keyPath: $0.index] == $0.slot }
    }

    /// Paints one layer. The first time, the crest takes a palette of its own
    /// with an entry for each layer, copied from what each layer wears, so a
    /// layer's color changes only that layer and never the sidebar.
    mutating func setForgeColor(_ color: BrandColor, of layer: BrowserCrestForgeLayer) {
        hasCustomAppearance = true
        if iconStyle == .simpleSymbol, layer.isIconFigure {
            symbolColor = color
            return
        }
        if !hasLayeredCrestPalette {
            let worn = BrowserCrestForgeLayer.all.map { layer -> BrandColor in
                let colors = crest.layerColors(spaceColors: self.colors)
                let index = crest[keyPath: layer.index]
                return colors.indices.contains(index) ? colors[index] : colors[0]
            }
            crest.palette = ColorPalette(colors: worn)
            for layer in BrowserCrestForgeLayer.all { crest[keyPath: layer.index] = layer.slot }
        }
        crest.palette?[layer.slot] = color
    }

    /// The fill one layer wears, with the gradient its palette entry runs
    /// into; an icon's figure wears the icon's accent.
    func forgeFill(of layer: BrowserCrestForgeLayer) -> CrestColorFill {
        if iconStyle == .simpleSymbol, layer.isIconFigure { return accentFill }
        return crestLayerFill(crest[keyPath: layer.index])
    }

    /// Paints one layer with `fill`, a color or a gradient. The first time,
    /// the crest takes a palette of its own with an entry for each layer,
    /// copied from what each layer wears, gradients too.
    mutating func setForgeFill(_ fill: CrestColorFill, of layer: BrowserCrestForgeLayer) {
        guard let color = fill.colors.first else { return }
        if iconStyle == .simpleSymbol, layer.isIconFigure {
            accentFill = fill
            return
        }
        let worn =
            hasLayeredCrestPalette
            ? crest.paletteGradients
            : PaletteGradients(
                slots: BrowserCrestForgeLayer.all.map {
                    Self.gradient(after: crestLayerFill(crest[keyPath: $0.index])) ?? Self.plainGradient
                })
        setForgeColor(color, of: layer)
        crest.paletteGradients = Self.gradients(worn, setting: fill, at: layer.slot)
    }
}
