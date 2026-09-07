import SwiftUI

struct BrowserSpaceAppearanceChoices: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String
    let page: BrowserSpaceAppearancePage
    let compact: Bool
    var dense = false
    let navigate: (BrowserSpaceAppearancePage) -> Void

    var body: some View {
        switch page {
        case .presets:
            VStack(spacing: dense ? 12 : 20) {
                customOption
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BrowserSpaceBrandingPreset.curated) { preset in
                        BrowserSpacePresetCard(
                            preset: preset, isSelected: preset.isSelected(in: branding), dense: dense
                        ) {
                            branding = preset.applying(to: branding)
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Button("Use an icon instead") { navigate(.icon) }
                        Spacer()
                        Button("Customize this crest", systemImage: "arrow.right") { navigate(.customize) }
                            .disabled(branding.iconStyle != .layeredCrest)
                    }
                    VStack(alignment: .leading, spacing: 16) { templateActions }
                }
                .buttonStyle(.plain)
                .font(CrestTypography.sans(dense ? 12 : 14))
                .foregroundStyle(CrestBrandTheme.accentText)
            }
        case .customize:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                ForEach(BrowserSpaceAppearancePage.details) { detail in
                    Button {
                        navigate(detail)
                    } label: {
                        VStack(spacing: 8) {
                            detailPreview(detail, size: dense ? 86 : 98)
                                .frame(maxWidth: .infinity)
                                .frame(height: dense ? 86 : 98)
                            HStack {
                                Text(detail.shortTitle).font(CrestTypography.sans(dense ? 14 : 16, weight: .semibold))
                                Spacer()
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .frame(height: dense ? 144 : 156)
                        .browserOnboardingPanel()
                        .clipShape(.rect(cornerRadius: 16))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .crest:
            crestOptions(BrowserSpaceCrestBackplate.allCases, keyPath: \.backplate)
        case .pattern:
            crestOptions(BrowserSpaceCrestChargeLayout.allCases, keyPath: \.chargeLayout)
        case .icon:
            BrowserSpaceAppearanceIconChoices(branding: $branding, symbol: $symbol)
        case .shape:
            crestOptions(BrowserSpaceCrestBackplate.allCases, keyPath: \.backplate)
        case .emblem:
            crestOptions(
                branding.crest.symbol == .oak ? BrowserSpaceCrestSymbol.allCases : BrowserSpaceCrestSymbol.selectable,
                keyPath: \.symbol)
        case .border:
            crestOptions(BrowserSpaceCrestTrim.allCases, keyPath: \.trim)
        case .layout:
            crestOptions(BrowserSpaceCrestChargeLayout.allCases, keyPath: \.chargeLayout)
        case .division:
            crestOptions(BrowserSpaceCrestFieldDivision.allCases, keyPath: \.fieldDivision)
        case .band:
            crestOptions(BrowserSpaceCrestOrdinary.allCases, keyPath: \.ordinary)
        case .palette:
            BrowserSpaceAppearancePaletteChoices(branding: $branding, compact: compact)
        case .background:
            VStack(alignment: .leading, spacing: 28) {
                Text("Contrast and intensity").font(CrestTypography.sans(16, weight: .semibold))
                BrowserSpaceAppearanceFinish(branding: $branding)
                Divider()
                Text("Background styles").font(CrestTypography.sans(16, weight: .semibold))
                BrowserSpaceAppearanceBackgroundChoices(branding: $branding)
            }
        case .finish:
            BrowserSpaceAppearanceFinish(branding: $branding)
        }
    }

    @ViewBuilder private var templateActions: some View {
        Button("Use an icon instead") { navigate(.icon) }
        Button("Customize this crest", systemImage: "arrow.right") { navigate(.customize) }
            .disabled(branding.iconStyle != .layeredCrest)
    }

    private var customOption: some View {
        Button {
            branding = BrowserSpaceAppearanceLanding.customStart
            navigate(.customize)
        } label: {
            HStack(spacing: 12) {
                BrowserSpaceCrestIcon(branding: BrowserSpaceAppearanceLanding.customStart, size: dense ? 32 : 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Custom").font(CrestTypography.sans(dense ? 13 : 15, weight: .semibold))
                    Text("Start with a simple crest").font(CrestTypography.sans(11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(dense ? 10 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .browserOnboardingPanel()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("space-branding-custom")
    }

    private func crestOptions<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ options: [Option], keyPath: WritableKeyPath<BrowserSpaceCrest, Option>
    ) -> some View {
        BrowserSpaceCrestOptionGallery(
            branding: $branding, options: options, keyPath: keyPath, compact: compact,
            regularMinimumWidth: 112, compactMinimumWidth: 100, iconSize: 70, columns: columns
        )
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 2 : 3)
    }

    private func detailBranding(_ detail: BrowserSpaceAppearancePage) -> BrowserSpaceBranding {
        var preview = branding
        switch detail {
        case .crest, .shape: preview.crest.backplate = .circle
        case .emblem: preview.crest.symbol = .sun
        case .border: preview.crest.trim = .doubleRing
        case .layout: preview.crest.chargeLayout = .trio
        case .pattern, .division: preview.crest.fieldDivision = .quarterly
        case .band: preview.crest.ordinary = .chevron
        default: break
        }
        return preview
    }

    @ViewBuilder private func detailPreview(_ detail: BrowserSpaceAppearancePage, size: CGFloat) -> some View {
        if detail == .palette {
            HStack(spacing: 4) {
                ForEach(Array(branding.colors.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 10).fill(color.color)
                }
            }
        } else if detail == .background || detail == .finish {
            BrowserSpaceBannerBackground(branding: branding).clipShape(.rect(cornerRadius: 12))
        } else {
            BrowserSpaceCrestIcon(branding: detailBranding(detail), size: size)
        }
    }
}

/// The page owns the selection so these controls can stay above its scrolling choices.
struct BrowserSpaceAppearancePicker: View {
    let pages: [BrowserSpaceAppearancePage]
    let selection: BrowserSpaceAppearancePage
    let select: (BrowserSpaceAppearancePage) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Button {
                    select(page)
                } label: {
                    Text(page.shortTitle)
                        .font(CrestTypography.sans(13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            selection == page ? CrestBrandPalette.butter : .clear, in: .rect(cornerRadius: 10)
                        )
                        .foregroundStyle(selection == page ? CrestBrandPalette.ink : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == page ? .isSelected : [])
            }
        }
    }
}
