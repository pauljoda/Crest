import SwiftUI

/// A square choice whose face is the interface it chooses, drawn small and
/// still, with its title under it. One of a row is chosen at a time.
///
/// The preview is laid out at `previewSize`, the size the real interface
/// would take, then scaled down whole into the face, so it shows exactly what
/// choosing it gives.
struct CrestPreviewButton<Preview: View>: View {
    // MARK: - Variables

    let title: Text
    let isSelected: Bool
    /// The size the preview is laid out at before it is scaled into the face.
    let previewSize: CGSize
    var faceSize: CGFloat = CrestPreviewButtonMetrics.regularFace
    /// Optional cache key for static previews. When supplied, the preview is
    /// rendered once into a backing bitmap at display scale and reused across
    /// scroll frames until the key or display scale changes.
    var snapshotKey: AnyHashable? = nil
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Actions - Drawing

    var body: some View {
        let inner = faceSize - 2 * CrestPreviewButtonMetrics.facePadding
        let scale = min(1, inner / max(previewSize.width, previewSize.height, 1))
        Button(action: action) {
            // The preview hangs over a frame of the face's size, so the size
            // it is laid out at never reaches the layout around the button.
            Color.clear
                .frame(width: inner, height: inner)
                .overlay {
                    previewSurface(inner: inner, scale: scale)
                }
                .clipShape(.rect(cornerRadius: CrestPreviewButtonMetrics.previewCornerRadius, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .buttonStyle(CrestPreviewButtonStyle(title: title, isSelected: isSelected, faceSize: faceSize))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func previewSurface(inner: CGFloat, scale: CGFloat) -> some View {
        if let snapshotKey,
            let image = CrestPreviewSnapshotCache.image(
                key: snapshotKey,
                colorScheme: colorScheme,
                innerSize: inner,
                previewSize: previewSize,
                scale: scale,
                displayScale: displayScale,
                preview: preview
            )
        {
            Image(decorative: image, scale: displayScale)
                .resizable()
                .frame(width: inner, height: inner)
        } else {
            preview()
                .frame(width: previewSize.width, height: previewSize.height)
                .scaleEffect(scale)
        }
    }
}

/// Caches rasterized `CGImage` snapshots of static preview cards so scrolling
/// Settings never re-composites nested miniature browser window hierarchies.
@MainActor
private enum CrestPreviewSnapshotCache {
    private struct CacheKey: Hashable {
        let contentKey: AnyHashable
        let colorScheme: ColorScheme
        let widthBucket: Int
        let previewWidthBucket: Int
        let previewHeightBucket: Int
        let scaleBucket: Int
    }

    private static var images: [CacheKey: CGImage] = [:]

    static func image<Preview: View>(
        key: AnyHashable,
        colorScheme: ColorScheme,
        innerSize: CGFloat,
        previewSize: CGSize,
        scale: CGFloat,
        displayScale: CGFloat,
        preview: () -> Preview
    ) -> CGImage? {
        let cacheKey = CacheKey(
            contentKey: key,
            colorScheme: colorScheme,
            widthBucket: Int((innerSize * 2).rounded()),
            previewWidthBucket: Int((previewSize.width * 2).rounded()),
            previewHeightBucket: Int((previewSize.height * 2).rounded()),
            scaleBucket: Int((displayScale * 10).rounded())
        )
        if let cached = images[cacheKey] { return cached }
        let content = Color.clear
            .frame(width: innerSize, height: innerSize)
            .overlay {
                preview()
                    .frame(width: previewSize.width, height: previewSize.height)
                    .scaleEffect(scale)
            }
            .clipped()
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(1, displayScale)
        renderer.proposedSize = ProposedViewSize(width: innerSize, height: innerSize)
        guard let cgImage = renderer.cgImage else { return nil }
        if images.count >= 48 { images.removeAll(keepingCapacity: true) }
        images[cacheKey] = cgImage
        return cgImage
    }
}

/// Measurements every preview button shares.
enum CrestPreviewButtonMetrics {
    /// A preview button in a settings group on the Mac.
    static let regularFace: CGFloat = 152
    /// A preview button three to a row on a phone.
    static let compactFace: CGFloat = 96
    static let facePadding: CGFloat = 7
    static let faceCornerRadius: CGFloat = CrestRadius.card
    static let previewCornerRadius: CGFloat = CrestRadius.card - 7
    static let ringWidth: CGFloat = 3
    static let ringGap: CGFloat = 2
    static let titleSpacing: CGFloat = 9
}

/// The face, ring and title around a preview button's preview, with the
/// selectable surface's hover, press and focus.
private struct CrestPreviewButtonStyle: ButtonStyle {
    let title: Text
    let isSelected: Bool
    let faceSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        CrestPreviewButtonBody(
            title: title, isSelected: isSelected, faceSize: faceSize, configuration: configuration)
    }
}

private struct CrestPreviewButtonBody: View {
    // MARK: - Variables

    let title: Text
    let isSelected: Bool
    let faceSize: CGFloat
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    // MARK: - Actions - Drawing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CrestPreviewButtonMetrics.faceCornerRadius, style: .continuous)
        let tint = CrestBrandTheme.accent
        VStack(spacing: CrestPreviewButtonMetrics.titleSpacing) {
            configuration.label
                .padding(CrestPreviewButtonMetrics.facePadding)
                .frame(width: faceSize, height: faceSize)
                .background(fill(tint: tint), in: shape)
                .overlay {
                    shape.strokeBorder(
                        CrestBrandTheme.line, lineWidth: contrast == .increased ? 1 : CrestLayout.hairline)
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CrestPreviewButtonMetrics.faceCornerRadius + CrestPreviewButtonMetrics.ringGap
                            + CrestPreviewButtonMetrics.ringWidth,
                        style: .continuous
                    )
                    .strokeBorder(tint, lineWidth: CrestPreviewButtonMetrics.ringWidth)
                    .padding(-(CrestPreviewButtonMetrics.ringGap + CrestPreviewButtonMetrics.ringWidth))
                    .opacity(isSelected ? 1 : 0)
                }
                .crestFocusShape(shape)
                .crestPressFeedback(isPressed: configuration.isPressed, isEnabled: isEnabled)
            title
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
        .contentShape(.rect)
        .animation(CrestMotion.press.unlessReducingMotion(reduceMotion), value: isSelected)
        .onHover { isHovering = $0 && isEnabled }
    }

    private func fill(tint: Color) -> Color {
        switch (isSelected, configuration.isPressed, isHovering) {
        case (true, _, _):
            tint.opacity(CrestSelectableCardMetrics.selectedFillOpacity)
        case (false, true, _):
            CrestColor.selection
        case (false, false, true):
            CrestColor.hover
        case (false, false, false):
            CrestColor.chromeSurface
        }
    }
}

#if DEBUG
    #Preview("Preview buttons") {
        @Previewable @State var selected = 0
        HStack(spacing: 20) {
            ForEach(0..<3) { index in
                CrestPreviewButton(
                    title: Text(["Heraldic", "Modern", "Simple"][index]), isSelected: selected == index,
                    previewSize: CGSize(width: 400, height: 400), action: { selected = index }
                ) {
                    RoundedRectangle(cornerRadius: 24).fill([Color.red, .blue, .gray][index].gradient)
                }
            }
        }
        .padding(40)
    }
#endif
