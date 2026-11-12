import SwiftUI

/// A Space's look in the Modern style: a set of colors, whether they run as a
/// gradient or stand solid, how strongly the sidebar wears them, how much
/// grain lies over them, which way a gradient runs, and a plain icon.
/// Choosing colors gives a Space in a banner the modern gradient. The last
/// choice is a gradient of the person's own, whose two ends show under the
/// color sets while it is chosen.
struct BrowserSpaceModernEditor: View {
    // MARK: - Variables

    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    /// Whether the person chose the custom gradient, which shows its ends
    /// before either one changes.
    @State private var choosesCustom = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The color sets a modern Space may wear: the accents' own, each
    /// scheme's, then each template's sidebar colors.
    private var presets: [[BrandColor]] {
        SpaceAccent.all.map(\.legacyColors) + SpaceScheme.all.map { Array($0.look.colors.colors) }
            + SpaceHouse.all.map { Array($0.look.colors.colors) }
    }

    /// Whether the custom gradient is the choice: chosen, or already worn
    /// in place of a color set.
    private var showsCustom: Bool {
        choosesCustom || (branding.themeMode == .gradient && !presets.contains(branding.colors.colors))
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 36), spacing: CrestSpacing.small)], spacing: CrestSpacing.small
            ) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                    swatch(preset)
                }
                customSwatch
            }
            .padding(.vertical, CrestSpacing.extraSmall)
            .accessibilityIdentifier("space-modern-colors")
            if showsCustom {
                BrowserSpaceCustomGradientEnds(branding: $branding)
            }
        } header: {
            CrestSettingsSectionHeading(title: "Colors")
        }
        Section {
            CrestSettingRow("Fill", setting: fill.resettable("Fill")) {
                Picker("Fill", selection: fill.binding) {
                    Text("Gradient").tag(Bool?.some(true))
                    Text("Solid").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                #if os(macOS)
                    .fixedSize()
                #endif
                .accessibilityIdentifier("space-modern-fill")
            }
            BrowserSpaceIntensityRow(branding: $branding)
            BrowserSpaceTextureRow(branding: $branding)
            if branding.themeMode == .gradient {
                BrowserSpaceGradientAngleRow(angle: angle, color: branding.secondaryColor.color)
            }
        }
        BrowserSpaceIconSection(branding: $branding, symbol: $symbol)
    }

    private func swatch(_ preset: [BrandColor]) -> some View {
        CrestSelectableCard(
            isSelected: !showsCustom && branding.colors.colors == preset,
            accessibilityLabel: Text(preset.map { String(localized: $0.title) }.joined(separator: ", ")),
            density: .swatch
        ) {
            revealsCustom(false)
            $branding.editorUpdate { look in
                look.colors = ColorPalette(colors: preset)
                if look.themeMode == .banner && look.bannerPattern != .solid {
                    look = look.inModernFill
                }
                look.hasCustomAppearance = true
            }
        } content: {
            Circle()
                .fill(LinearGradient(colors: preset.map(\.color), startPoint: .top, endPoint: .bottom))
                .frame(width: 28, height: 28)
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
        }
    }

    /// The last choice after the color sets: the Space's own gradient once
    /// it is chosen, and a plus before.
    private var customSwatch: some View {
        CrestSelectableCard(isSelected: showsCustom, accessibilityLabel: Text("Custom gradient"), density: .swatch) {
            revealsCustom(true)
        } content: {
            Circle()
                .fill(
                    showsCustom
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: branding.colors.colors.map(\.color), startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(CrestColor.chromeSurface)
                )
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .opacity(showsCustom ? 0 : 1)
                }
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
        }
        .help(Text("Custom gradient"))
        .accessibilityIdentifier("space-modern-custom-gradient")
    }

    // MARK: - Actions - Settings

    /// Shows the custom gradient's ends under the color sets, or hides them.
    private func revealsCustom(_ reveals: Bool) {
        withAnimation(CrestMotion.disclosure.unlessReducingMotion(reduceMotion)) { choosesCustom = reveals }
    }

    /// Whether the sidebar runs its colors as a gradient or stands solid,
    /// or neither while it wears a patterned banner.
    private var fill: CrestSettingValue<Bool?> {
        CrestSettingValue(
            Binding(
                get: {
                    branding.themeMode == .gradient ? true : branding.bannerPattern == .solid ? false : nil
                },
                set: { gradient in
                    guard let gradient else { return }
                    $branding.editorUpdate {
                        $0.themeMode = gradient ? .gradient : .banner
                        if !gradient { $0.bannerPattern = .solid }
                        $0.hasCustomAppearance = true
                    }
                }),
            default: true)
    }

    /// Which way the gradient runs, from the angle Modern starts it at.
    private var angle: CrestSettingValue<Double> {
        CrestSettingValue(
            Binding(
                get: { branding.gradientAngle },
                set: { angle in
                    $branding.editorUpdate {
                        $0.gradientAngle = angle
                        $0.hasCustomAppearance = true
                    }
                }),
            default: SetupLook.modern.gradientAngle ?? 0)
    }
}

/// The two ends of a Space's own gradient, each chosen with the system color
/// picker, in a row under the color sets. They sit on the page rather than
/// in a popover, which the system picker would close as it took focus.
private struct BrowserSpaceCustomGradientEnds: View {
    // MARK: - Variables

    @Binding var branding: SpaceBranding

    // MARK: - Actions - Drawing

    var body: some View {
        CrestSettingRow("Custom gradient") {
            HStack(spacing: CrestSpacing.large) {
                end("From", 0)
                end("To", 1)
            }
        }
        .accessibilityIdentifier("space-modern-custom-gradient-ends")
    }

    /// One end of the gradient as a round swatch, named under it.
    private func end(_ title: LocalizedStringResource, _ index: Int) -> some View {
        VStack(spacing: CrestSpacing.extraSmall) {
            CrestCustomColorSwatch(title: title, color: color(at: index), isSelected: true, tint: CrestBrandTheme.line)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions - Settings

    /// One end of the gradient: its first color, or its last.
    private func color(at index: Int) -> Binding<Color> {
        Binding(
            get: {
                let colors = branding.colors.colors
                return (index == 0 ? colors.first : colors.last)?.color ?? .gray
            },
            set: { color in
                $branding.editorUpdate { look in
                    let colors = look.colors.colors
                    var ends = [colors.first ?? BrandColor(color: color), colors.last ?? BrandColor(color: color)]
                    ends[index] = BrandColor(color: color)
                    look.colors = ColorPalette(colors: ends)
                    if look.themeMode != .gradient { look = look.inModernFill }
                    look.hasCustomAppearance = true
                }
            })
    }
}

extension SpaceBranding {
    /// This look run as Modern's gradient, keeping the icon it wears, so a
    /// crest chosen under Advanced stays as the colors change.
    fileprivate var inModernFill: SpaceBranding {
        var look = SetupLook.modern.applying(to: self)
        look.iconStyle = iconStyle
        return look
    }
}

#if DEBUG
    #Preview("Modern editor") {
        @Previewable @State var branding = BrowserCustomizationStyle.modern.look(
            for: SpaceHouse.winter.look, remembered: nil)
        @Previewable @State var symbol = "briefcase.fill"
        Form {
            BrowserSpaceModernEditor(branding: $branding, symbol: $symbol)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }
#endif
