import SwiftUI

/// The crest on the Space's own sidebar field, beside the Space's colors:
/// its Background and Accent, its Pattern while the sidebar shows one, and
/// each part of the crest while `showsCrestColors`.
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
    @State private var openSidebarColor: BrowserSpaceBrandColorRole?

    var body: some View {
        stage
            .overlay(alignment: .topTrailing) { tools }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("space-forge-stage")
    }

    /// The crest beside its colors on the Mac; on iPhone and iPad, beside them
    /// where there's room for both and above them where there isn't.
    @ViewBuilder private var stage: some View {
        #if os(macOS)
            wideStage
        #else
            ViewThatFits(in: .horizontal) {
                wideStage
                compactStage
            }
        #endif
    }

    private var wideStage: some View {
        HStack(spacing: BrowserCrestForgeMetrics.stageSpacing) {
            VStack(spacing: 12) {
                mark(size: BrowserCrestForgeMetrics.crestSize)
                nameField
            }
            swatches(columnWidth: BrowserCrestForgeMetrics.swatchColumnWidth)
            Spacer(minLength: 0)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, minHeight: BrowserCrestForgeMetrics.stageHeight, alignment: .leading)
        .background { field(shadeFrom: .leading, to: .trailing) }
    }

    private var compactStage: some View {
        VStack(spacing: 14) {
            mark(size: BrowserCrestForgeMetrics.compactCrestSize)
            nameField
            swatches(
                columnWidth: BrowserCrestForgeMetrics.compactSwatchColumnWidth,
                sidebarColumnWidth: BrowserCrestForgeMetrics.compactSidebarSwatchColumnWidth)
        }
        .padding(.top, 48)
        .padding(.horizontal, 8)
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

    /// The colors in columns of `columnWidth`: the Space's, which take wider
    /// columns where that keeps their names whole, then the crest's parts.
    private func swatches(columnWidth: CGFloat, sidebarColumnWidth: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            swatchGroup("Colors") {
                ForEach(shownRoles) { role in
                    sidebarSwatch(role, columnWidth: sidebarColumnWidth ?? columnWidth)
                }
            }
            if showsCrestColors, branding.iconStyle == .layeredCrest {
                swatchGroup(branding.iconStyle.title) {
                    ForEach(BrowserCrestForgeLayer.shown(by: branding)) { layer in
                        layerSwatch(layer, columnWidth: columnWidth)
                    }
                }
            }
        }
    }

    /// The Space's colors the stage offers: Background and Accent, and
    /// Pattern while the sidebar draws a pattern.
    private var shownRoles: [BrowserSpaceBrandColorRole] {
        branding.showsPattern ? BrowserSpaceBrandColorRole.all : [.background, .accent]
    }

    /// The Space's texture, which its Background's picker sets.
    private var texture: Binding<Double> {
        Binding(
            get: { branding.textureStrength },
            set: { strength in
                branding.textureStrength = strength
                branding.hasCustomAppearance = true
                branding = branding.normalized()
            })
    }

    /// The fill a Space color wears, which a pick sets as the Space's wells do.
    private func fill(of role: BrowserSpaceBrandColorRole) -> Binding<CrestColorFill> {
        Binding(
            get: { branding.wellFill(role) },
            set: { fill in
                branding.setWellFill(fill, of: role)
                branding = branding.normalized()
            })
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
        .padding(12)
    }

    private func swatchGroup<Content: View>(
        _ title: LocalizedStringResource, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 2) { content() }
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

    private func sidebarSwatch(_ role: BrowserSpaceBrandColorRole, columnWidth: CGFloat) -> some View {
        BrowserCrestForgeSwatch(
            title: role.title, fill: branding.wellFill(role), isOpen: openSidebarColor == role,
            columnWidth: columnWidth
        ) {
            openSidebarColor = role
        }
        .crestPopover(
            isPresented: Binding(
                get: { openSidebarColor == role }, set: { if !$0, openSidebarColor == role { openSidebarColor = nil } }),
            arrowEdge: .bottom
        ) {
            CrestColorPopover(fill: fill(of: role), texture: role == .background ? texture : nil)
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
            .crestInteractiveSurface(isSelected: isOpen, isHovering: isHovering, cornerRadius: 10)
            .contentShape(.rect(cornerRadius: 10))
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
    static let swatchColumnWidth: CGFloat = 62
    static let compactSwatchColumnWidth: CGFloat = 52
    static let compactSidebarSwatchColumnWidth: CGFloat = 76
    static let nameWidth: CGFloat = 240
    static let tileCrestSize: CGFloat = 56
    /// A Space's pages are wider than other settings pages, for the stage.
    static let columnWidth: CGFloat = 720
}
