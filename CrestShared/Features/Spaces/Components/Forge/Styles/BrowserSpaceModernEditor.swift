import SwiftUI

/// A Space's look in the Modern style: a set of colors, whether they run as a
/// gradient or stand solid, how strongly the sidebar wears them, which way a
/// gradient runs, and a plain icon.
/// Choosing colors gives a Space in a banner the modern gradient.
struct BrowserSpaceModernEditor: View {
    // MARK: - Types

    /// Which way a gradient runs down the sidebar, by its angle.
    private struct Direction: Hashable {
        static let all = [
            Direction(title: "Down", angle: 90), Direction(title: "Diagonal", angle: 45),
            Direction(title: "Across", angle: 0),
        ]

        let title: LocalizedStringResource
        let angle: Double

        static func == (lhs: Direction, rhs: Direction) -> Bool { lhs.angle == rhs.angle }
        func hash(into hasher: inout Hasher) { hasher.combine(angle) }
    }

    // MARK: - Variables

    @Binding var branding: SpaceBranding
    @Binding var symbol: String

    /// The color sets a modern Space may wear: the accents' own, each
    /// scheme's, then each template's sidebar colors.
    private var presets: [[BrandColor]] {
        SpaceAccent.all.map(\.legacyColors) + SpaceScheme.all.map { Array($0.look.colors.colors) }
            + SpaceHouse.all.map { Array($0.look.colors.colors) }
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
                BrowserSpaceCustomGradient(
                    branding: $branding,
                    isCustom: branding.themeMode == .gradient && !presets.contains(branding.colors.colors))
            }
            .padding(.vertical, CrestSpacing.extraSmall)
            .accessibilityIdentifier("space-modern-colors")
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
            if branding.themeMode == .gradient {
                CrestSettingRow("Direction", setting: direction.resettable("Direction")) {
                    Picker("Direction", selection: direction.binding) {
                        ForEach(Direction.all, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    #if os(macOS)
                        .fixedSize()
                    #endif
                }
            }
        }
        BrowserSpaceIconSection(branding: $branding, symbol: $symbol)
    }

    private func swatch(_ preset: [BrandColor]) -> some View {
        CrestSelectableCard(
            isSelected: branding.colors.colors == preset,
            accessibilityLabel: Text(preset.map { String(localized: $0.title) }.joined(separator: ", ")),
            density: .swatch
        ) {
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

    // MARK: - Actions - Settings

    /// Whether the sidebar runs its colors as a gradient; otherwise it stands
    /// solid in its background color.
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

    private var direction: CrestSettingValue<Direction?> {
        CrestSettingValue(
            Binding(
                get: { Direction.all.first { $0.angle == branding.gradientAngle } },
                set: { chosen in
                    guard let chosen else { return }
                    $branding.editorUpdate {
                        $0.gradientAngle = chosen.angle
                        $0.hasCustomAppearance = true
                    }
                }),
            default: Direction.all.first)
    }
}

/// The last choice after the color sets: a gradient of the person's own,
/// from one color to another, each chosen with the system color picker.
private struct BrowserSpaceCustomGradient: View {
    // MARK: - Variables

    @Binding var branding: SpaceBranding
    let isCustom: Bool
    @State private var isChoosing = false

    // MARK: - Actions - Drawing

    var body: some View {
        CrestSelectableCard(isSelected: isCustom, accessibilityLabel: Text("Custom gradient"), density: .swatch) {
            isChoosing = true
        } content: {
            Circle()
                .fill(isCustom ? AnyShapeStyle(gradient) : AnyShapeStyle(CrestColor.chromeSurface))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .opacity(isCustom ? 0 : 1)
                }
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
        }
        .help(Text("Custom gradient"))
        .accessibilityIdentifier("space-modern-custom-gradient")
        .crestPopover(isPresented: $isChoosing) {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                Text("Custom gradient").font(.headline)
                HStack(spacing: CrestSpacing.large) {
                    end("From", 0)
                    end("To", 1)
                }
            }
            .padding(14)
            .fixedSize()
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: branding.colors.colors.map(\.color), startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Actions - Settings

    /// One end of the gradient as a round swatch, named under it.
    private func end(_ title: LocalizedStringResource, _ index: Int) -> some View {
        VStack(spacing: CrestSpacing.extraSmall) {
            CrestCustomColorSwatch(title: title, color: color(at: index), isSelected: isCustom)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

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
