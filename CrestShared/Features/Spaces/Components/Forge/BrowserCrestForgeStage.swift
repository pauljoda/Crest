import SwiftUI

/// The crest on the Space's own sidebar field, the page's preview of every
/// change, beside the color of each part of the crest while
/// `showsCrestColors`. The Space's own colors have a section of their own
/// under the templates.
struct BrowserCrestForgeStage: View {
    @Binding var branding: SpaceBranding
    let symbol: String
    /// Whether the stage shows a color for each part of the crest, as More
    /// Customization does.
    var showsCrestColors = false
    /// The Space's name, which the stage lets a person edit where nothing
    /// else on the page does.
    var name: Binding<String>? = nil
    let canUndo: Bool
    let shuffle: () -> Void
    let undo: () -> Void
    /// Shows a step of the Forge, for a color whose part the crest doesn't draw.
    let openStep: (BrowserCrestStudioStep) -> Void

    @State private var openLayer: BrowserCrestForgeLayer?

    var body: some View {
        stage
            .overlay(alignment: .topTrailing) { tools }
            .clipShape(.rect(cornerRadius: CrestRadius.card, style: .continuous))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("space-forge-stage")
    }

    /// The crest beside its parts' colors on the Mac; on iPhone and iPad,
    /// beside them where there's room for both and above them where there
    /// isn't, and alone under the stage's tools.
    @ViewBuilder private var stage: some View {
        #if os(macOS)
            wideStage
        #else
            if showsSwatches {
                ViewThatFits(in: .horizontal) {
                    wideStage
                    compactStage
                }
            } else {
                compactStage
            }
        #endif
    }

    /// Whether the stage shows the crest's parts' colors beside it, which
    /// it then stands to the leading side of; alone, it stands in the middle.
    private var showsSwatches: Bool {
        showsCrestColors && branding.iconStyle == .layeredCrest
    }

    private var wideStage: some View {
        HStack(spacing: BrowserCrestForgeMetrics.stageSpacing) {
            VStack(spacing: CrestSpacing.medium) {
                mark(size: BrowserCrestForgeMetrics.crestSize)
                nameField
            }
            if showsSwatches {
                swatches(columnWidth: BrowserCrestForgeMetrics.swatchColumnWidth)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, showsSwatches ? 28 : CrestSpacing.large)
        .padding(.trailing, CrestSpacing.large)
        .frame(
            maxWidth: .infinity, minHeight: BrowserCrestForgeMetrics.stageHeight,
            alignment: showsSwatches ? .leading : .center
        )
        .background { field(shadeFrom: .leading, to: .trailing) }
    }

    private var compactStage: some View {
        VStack(spacing: 14) {
            mark(size: BrowserCrestForgeMetrics.compactCrestSize)
            nameField
            if showsSwatches {
                swatches(columnWidth: BrowserCrestForgeMetrics.compactSwatchColumnWidth)
            }
        }
        .padding(.top, 48)
        .padding(.horizontal, CrestSpacing.small)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background { field(shadeFrom: .top, to: .bottom) }
    }

    private func mark(size: CGFloat) -> some View {
        BrowserCrestStudioMark(branding: branding, symbol: symbol, size: size)
            .accessibilityLabel("Crest preview")
    }

    /// The Space's name under its crest, where the page doesn't already
    /// carry it.
    @ViewBuilder private var nameField: some View {
        if let name {
            BrowserInlineSpaceName(name: name, size: 20, titleFont: .title3.weight(.semibold))
                .frame(maxWidth: BrowserCrestForgeMetrics.nameWidth)
        }
    }

    /// The crest's parts' colors in columns of `columnWidth`.
    private func swatches(columnWidth: CGFloat) -> some View {
        swatchGroup(branding.iconStyle.title) {
            ForEach(BrowserCrestForgeLayer.shown(by: branding)) { layer in
                layerSwatch(layer, columnWidth: columnWidth)
            }
        }
    }

    /// The Space's own sidebar field, shaded toward the colors so they read.
    private func field(shadeFrom start: UnitPoint, to end: UnitPoint) -> some View {
        ZStack {
            BrowserSpaceBannerBackground(branding: branding)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.05), location: 0),
                    .init(color: .black.opacity(0.28), location: 0.62),
                    .init(color: .black.opacity(0.34), location: 1),
                ],
                startPoint: start, endPoint: end)
        }
    }

    private var tools: some View {
        HStack(spacing: 6) {
            Button("Shuffle", systemImage: "shuffle", action: shuffle)
                .accessibilityIdentifier("space-forge-shuffle")
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .disabled(!canUndo)
                .accessibilityIdentifier("space-forge-undo")
        }
        .crestGlassButtonStyle()
        .controlSize(.small)
        .padding(CrestSpacing.medium)
    }

    private func swatchGroup<Content: View>(
        _ title: LocalizedStringResource, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: CrestSpacing.extraExtraSmall) { content() }
        }
    }

    private func layerSwatch(_ layer: BrowserCrestForgeLayer, columnWidth: CGFloat) -> some View {
        let isDrawn = layer.isDrawn(by: branding)
        return BrowserCrestForgeSwatch(
            title: layer.title(in: branding), fill: branding.forgeFill(of: layer), isDrawn: isDrawn,
            hint: isDrawn ? nil : layer.enablingHint(for: branding), isOpen: openLayer == layer,
            columnWidth: columnWidth
        ) {
            // A part the crest doesn't draw opens the step that adds it.
            if isDrawn { openLayer = layer } else { openStep(layer.enablingStep(for: branding)) }
        }
        .crestPopover(
            isPresented: Binding(get: { openLayer == layer }, set: { if !$0, openLayer == layer { openLayer = nil } }),
            arrowEdge: .bottom
        ) {
            CrestColorPopover(
                fill: Binding(
                    get: { branding.forgeFill(of: layer) },
                    set: { fill in
                        branding.setForgeFill(fill, of: layer)
                        branding = branding.normalized()
                    })
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// One color on the stage, named by what it paints. A part the crest doesn't
/// draw shows its color faintly, says on hover how to add it, and leads there.
private struct BrowserCrestForgeSwatch: View {
    let title: LocalizedStringResource
    /// What the part wears: one color, or a gradient.
    let fill: CrestColorFill
    var isDrawn = true
    var hint: LocalizedStringResource? = nil
    let isOpen: Bool
    let columnWidth: CGFloat
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 6) {
                Circle()
                    .fill(fill.style)
                    .frame(width: BrowserCrestForgeMetrics.swatchSize, height: BrowserCrestForgeMetrics.swatchSize)
                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5) }
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .opacity(isDrawn ? 1 : 0.3)
                Text(title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isDrawn || isHovering ? 1 : 0.6)
            }
            .frame(width: columnWidth)
            .padding(.vertical, 6)
            .crestInteractiveSurface(
                isSelected: isOpen, isHovering: isHovering, cornerRadius: BrowserCrestForgeMetrics.swatchCornerRadius
            )
            .contentShape(.rect(cornerRadius: BrowserCrestForgeMetrics.swatchCornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(hint.map { Text($0) } ?? Text(fill.colors[0].title))
        .accessibilityLabel(Text(title))
        .accessibilityValue(fill.isGradient ? Text("Gradient") : Text(fill.colors[0].title))
        .accessibilityHint(hint.map { Text($0) } ?? Text(""))
    }
}

enum BrowserCrestForgeMetrics {
    static let crestSize: CGFloat = 188
    static let compactCrestSize: CGFloat = 148
    static let stageHeight: CGFloat = 284
    static let stageSpacing: CGFloat = 28
    static let swatchSize: CGFloat = 28
    /// A swatch's hover and selection surface, a step between the compact
    /// and control corners.
    static let swatchCornerRadius: CGFloat = 10
    static let swatchColumnWidth: CGFloat = 62
    static let compactSwatchColumnWidth: CGFloat = 52
    static let nameWidth: CGFloat = 240
    static let tileCrestSize: CGFloat = 56
    /// The room between the stage and the heading of the templates under it.
    static let stageHeadingSpacing = CrestSpacing.extraLarge
    /// A Space's pages are wider than other settings pages, for the stage.
    static let columnWidth: CGFloat = 720
}
