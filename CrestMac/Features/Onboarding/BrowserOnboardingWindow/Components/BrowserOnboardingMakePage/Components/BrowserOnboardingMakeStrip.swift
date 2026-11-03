import SwiftUI

/// One row of the sheet: what it changes, and a strip of choices.
struct BrowserOnboardingMakeSection<Accessory: View, Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(title)
                    .font(CrestTypography.sans(12, weight: .bold))
                    .foregroundStyle(CrestBrandTheme.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                accessory
            }
            content
        }
        .accessibilityElement(children: .contain)
    }
}

/// A row of choices, which scrolls sideways where the sheet is narrower
/// than the row.
struct BrowserOnboardingMakeStrip<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: spacing) { content }
                .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One choice on a strip: artwork on a tile, lit when chosen.
struct BrowserOnboardingMakeTile<Artwork: View>: View {
    let title: LocalizedStringResource
    let isSelected: Bool
    let select: () -> Void
    @ViewBuilder let artwork: Artwork

    var body: some View {
        CrestSelectableCard(
            isSelected: isSelected, accessibilityLabel: Text(title), density: .compact,
            tint: CrestBrandPalette.butter, action: select
        ) {
            artwork
                .frame(
                    width: BrowserOnboardingMakeMetrics.tileArtworkSize,
                    height: BrowserOnboardingMakeMetrics.tileArtworkSize
                )
        }
        .help(Text(title))
    }
}

/// One color, named by what it paints, which opens the templates' tinctures
/// to pick from. A part the crest doesn't draw shows faintly.
struct BrowserOnboardingMakeSwatch: View {
    let title: LocalizedStringResource
    var caption: LocalizedStringResource? = nil
    let color: BrandColor
    var isDrawn = true
    let select: (BrandColor) -> Void
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(color.color)
                    .frame(
                        width: BrowserOnboardingMakeMetrics.swatchSize, height: BrowserOnboardingMakeMetrics.swatchSize
                    )
                    .overlay { Circle().strokeBorder(CrestBrandPalette.paper.opacity(0.3), lineWidth: 1.5) }
                    .opacity(isDrawn ? 1 : 0.3)
                Text(title)
                    .font(CrestTypography.sans(10, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(color.title))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(color.title))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            BrowserCrestForgePalette(title: title, caption: caption, color: color, select: select)
                .presentationCompactAdaptation(.popover)
        }
    }
}
