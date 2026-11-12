import SwiftUI

/// What a first run changes on a modern Space: its colors, whether they run
/// as a gradient or stand solid, and its icon.
struct BrowserOnboardingModernSheet: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String

    /// The color sets a modern Space may wear: the accents' own, each
    /// scheme's, then each template's sidebar colors.
    private var presets: [[BrandColor]] {
        SpaceAccent.all.map(\.legacyColors) + SpaceScheme.all.map { Array($0.look.colors) }
            + SpaceHouse.all.map { Array($0.look.colors) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            colors
            fill
            icon
            Spacer(minLength: 0)
            Text("Patterns and crests: Settings › Spaces.")
                .font(CrestTypography.sans(12, weight: .medium))
                .foregroundStyle(CrestBrandTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var colors: some View {
        BrowserOnboardingMakeSection("Color") {
            VStack(alignment: .leading, spacing: 16) {
                BrowserOnboardingMakeStrip {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                        BrowserOnboardingModernPresetSwatch(
                            colors: preset, isSelected: Array(branding.colors) == preset
                        ) {
                            $branding.editorUpdate {
                                $0.colors = ColorPalette(colors: preset)
                                $0.hasCustomAppearance = true
                            }
                        }
                    }
                }
                BrowserOnboardingMakeStrip(spacing: 0) {
                    BrowserOnboardingSidebarSwatches(branding: $branding)
                }
            }
        }
    }

    private var fill: some View {
        BrowserOnboardingMakeSection("Fill") {
            Picker("Fill", selection: isGradient) {
                Text("Gradient").tag(true)
                Text("Solid").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var icon: some View {
        BrowserOnboardingIconSection(branding: $branding, symbol: $symbol)
    }

    // MARK: - Choices

    /// Whether the sidebar runs its colors as a gradient; otherwise it stands
    /// solid in its background color.
    private var isGradient: Binding<Bool> {
        Binding(
            get: { branding.themeMode == .gradient },
            set: { gradient in
                $branding.editorUpdate {
                    $0.themeMode = gradient ? .gradient : .banner
                    if !gradient { $0.bannerPattern = .solid }
                    $0.hasCustomAppearance = true
                }
            })
    }
}

/// A set of colors as one round swatch, running from the first to the last.
private struct BrowserOnboardingModernPresetSwatch: View {
    let colors: [BrandColor]
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        CrestSelectableCard(
            isSelected: isSelected,
            accessibilityLabel: Text(colors.map { String(localized: $0.title) }.joined(separator: ", ")),
            density: .swatch, tint: CrestBrandPalette.butter, action: select
        ) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 44, height: 44)
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
        }
    }
}
