import SwiftUI

/// A color a simple Space wears: its sidebar laid thinly in it over the
/// window, and its icon in it. The choices are the templates' tinctures that
/// read as a tint and as an icon on a light sidebar and a dark one.
struct BrowserSimpleSpaceColor: Hashable, Sendable {
    // MARK: - Static Variables

    static let all = [
        Tincture.rose, .dragonScarlet, .ember, .sunOr, .sage, .teal, .sky, .riverAzure, .indigo, .neutralGray,
    ].map(BrowserSimpleSpaceColor.init(tincture:))

    // MARK: - Variables

    let tincture: Tincture
    var color: BrandColor { tincture.color }

    // MARK: - Actions - Looks

    /// The choice `branding` wears, when it wears one: a simple look in one
    /// of these colors.
    static func worn(by branding: SpaceBranding) -> BrowserSimpleSpaceColor? {
        guard branding.colors.colors.count == 1, branding.themeMode == .gradient,
            let color = branding.colors.colors.first
        else { return nil }
        return all.first { $0.color == color }
    }

    /// Whether `branding` wears the simple look in a color of the person's
    /// own, rather than one of these.
    static func wearsCustom(_ branding: SpaceBranding) -> Bool {
        branding.colors.colors.count == 1 && branding.themeMode == .gradient && worn(by: branding) == nil
    }

    /// `branding` in the simple look, in `color`, keeping the intensity a
    /// simple look already has.
    static func look(in color: BrandColor, from branding: SpaceBranding) -> SpaceBranding {
        let wearsSimple = branding.colors.colors.count == 1 && branding.themeMode == .gradient
        var look = branding
        look.colors = ColorPalette(colors: [color])
        look = SetupLook.simple.applying(to: look)
        if wearsSimple { look.bannerStrength = branding.bannerStrength }
        look.hasCustomAppearance = true
        return look
    }

    /// `branding` in the simple look, in this color.
    func applied(to branding: SpaceBranding) -> SpaceBranding {
        Self.look(in: color, from: branding)
    }
}

/// One simple color as a round swatch to choose.
struct BrowserSimpleSpaceColorSwatch: View {
    let color: BrowserSimpleSpaceColor
    let isSelected: Bool
    var diameter: CGFloat = 28
    var tint: Color? = nil
    let select: () -> Void

    var body: some View {
        CrestSelectableCard(
            isSelected: isSelected, accessibilityLabel: Text(color.tincture.title), density: .swatch, tint: tint,
            action: select
        ) {
            Circle()
                .fill(color.color.color)
                .frame(width: diameter, height: diameter)
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
        }
    }
}

/// The last choice after the simple colors: a color of the person's own,
/// from the system color picker.
struct BrowserSimpleSpaceCustomColor: View {
    @Binding var branding: SpaceBranding
    var diameter: CGFloat = 28
    var tint: Color? = nil

    var body: some View {
        CrestCustomColorSwatch(
            title: "Custom color",
            color: Binding(
                get: { (branding.colors.colors.first ?? BrowserSimpleSpaceColor.all[0].color).color },
                set: { color in
                    $branding.editorUpdate { $0 = BrowserSimpleSpaceColor.look(in: BrandColor(color: color), from: $0) }
                }),
            isSelected: BrowserSimpleSpaceColor.wearsCustom(branding), diameter: diameter, tint: tint
        )
        .accessibilityIdentifier("space-simple-custom-color")
    }
}

#if DEBUG
    #Preview("Simple colors") {
        @Previewable @State var branding = BrowserSimpleSpaceColor.all[6].applied(to: SpaceHouse.winter.look)
        HStack(spacing: 8) {
            ForEach(BrowserSimpleSpaceColor.all, id: \.self) { color in
                BrowserSimpleSpaceColorSwatch(
                    color: color, isSelected: BrowserSimpleSpaceColor.worn(by: branding) == color
                ) {
                    branding = color.applied(to: branding)
                }
            }
            BrowserSimpleSpaceCustomColor(branding: $branding)
        }
        .padding(24)
    }
#endif
