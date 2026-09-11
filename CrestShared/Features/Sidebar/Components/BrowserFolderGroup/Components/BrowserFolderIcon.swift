import SwiftUI

/// The folder's symbol, in the same column the rows below give their favicons.
struct BrowserFolderIcon: View {
    let folder: BrowserFolder
    let isExpanded: Bool
    let metrics: BrowserFolderHeaderMetrics

    var body: some View {
        BrowserFolderArtwork(symbol: folder.symbol, color: folder.color, isExpanded: isExpanded)
            .modifier(BrowserFolderIconColumn(metrics: metrics, isExpanded: isExpanded))
            .accessibilityHidden(true)
    }
}

/// The shared folder drawing, with its optional symbol attached to the front plane.
struct BrowserFolderArtwork: View {
    let symbol: String
    let color: BrowserSpaceBrandColor
    var isExpanded = false

    var body: some View {
        BrowserFolderFaces(glyph: faceSymbol, color: color, isExpanded: isExpanded)
            .foregroundStyle(faceForeground)
    }

    private var faceForeground: Color {
        let scheme = BrowserSpaceForegroundPolicy.colorScheme(
            for: BrowserSpaceBranding(colors: [color], bannerStrength: 1, readabilityFade: 0))
        return scheme == .dark ? .white : .black
    }

    private var faceSymbol: Text? {
        if let emoji = BrowserIconSymbol.emoji(from: symbol) { return Text(emoji) }
        guard symbol != "folder", symbol != "folder.fill" else { return nil }
        return Text(Image(systemName: symbol))
    }
}

/// Holds the symbol in its column, and sizes it where the shell reads the row
/// from further away than a desk.
private struct BrowserFolderIconColumn: ViewModifier {
    let metrics: BrowserFolderHeaderMetrics
    let isExpanded: Bool
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var iconScale = 1.0

    func body(content: Content) -> some View {
        content
            .font(
                .system(
                    size: ((metrics.iconGlyphSize ?? 16) + 2) * BrowserSidebarDensityPolicy.scale(iconScale),
                    weight: metrics.iconGlyphWeight)
            )
            // Reserve the open front's projected edge without moving the title
            // when the folder toggles. The bottom hinge lowers its optical center.
            .offset(y: (isExpanded ? -1.5 : -0.5) * BrowserSidebarDensityPolicy.scale(iconScale))
            .frame(width: (metrics.iconWidth + 6) * BrowserSidebarDensityPolicy.scale(iconScale))
    }
}

/// Shared proportions and hinge angles for the folder's two flat faces.
private enum BrowserFolderGeometry {
    static let translation = 3.0
    static let yAngle = 32.0
    static let frontAngle = -30.0
    static let backAngle = 28.0
    static let perspective = -1.0 / 350.0
    static let tabHeight = 0.25
    static let tabStart = 0.42
    static let tabEnd = 0.58
    static let cornerDivisor = 7.0
}

private struct BrowserFolderFaces: View {
    let glyph: Text?
    let color: BrowserSpaceBrandColor
    let isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "folder").hidden().overlay {
            GeometryReader { proxy in
                let size = proxy.size
                let top = size.height * BrowserFolderGeometry.tabHeight
                let radius = size.width / BrowserFolderGeometry.cornerDivisor
                ZStack(alignment: .bottomLeading) {
                    Canvas { context, size in
                        let edgeInset: CGFloat = 0.5
                        context.translateBy(x: edgeInset, y: edgeInset)
                        let w = size.width - edgeInset * 2
                        let h = size.height - edgeInset * 2
                        let shoulder = top / 1.5
                        var path = Path()
                        path.move(to: CGPoint(x: radius, y: 0))
                        path.addLine(to: CGPoint(x: w * BrowserFolderGeometry.tabStart, y: 0))
                        path.addLine(to: CGPoint(x: w * BrowserFolderGeometry.tabEnd, y: shoulder))
                        path.addLine(to: CGPoint(x: w - radius, y: shoulder))
                        path.addArc(
                            center: CGPoint(x: w - radius, y: shoulder + radius), radius: radius,
                            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                        path.addLine(to: CGPoint(x: w, y: h - radius))
                        path.addArc(
                            center: CGPoint(x: w - radius, y: h - radius), radius: radius,
                            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                        path.addLine(to: CGPoint(x: radius, y: h))
                        path.addArc(
                            center: CGPoint(x: radius, y: h - radius), radius: radius,
                            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                        path.addLine(to: CGPoint(x: 0, y: radius))
                        path.addArc(
                            center: CGPoint(x: radius, y: radius), radius: radius,
                            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                        path.closeSubpath()
                        context.fill(path, with: .color(faceColor))
                        context.fill(path, with: .color(.black.opacity(0.22)))
                    }
                    .modifier(
                        BrowserFolderFaceProjection(front: false, openness: isExpanded ? 1 : 0)
                    )
                    Canvas { context, size in
                        let edgeInset: CGFloat = 0.5
                        let path = Path(
                            roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: edgeInset, dy: edgeInset),
                            cornerRadius: max(0, radius - edgeInset))
                        context.fill(path, with: .color(faceColor))
                        var tint = context
                        tint.opacity = 0.12
                        tint.fill(path, with: .color(.white))
                        if let glyph {
                            context.draw(
                                glyph.font(.system(size: size.height * 0.5, weight: .semibold)),
                                at: CGPoint(x: size.width / 2, y: size.height / 2))
                        }
                    }
                    .frame(height: max(1, size.height - top))
                    .modifier(
                        BrowserFolderFaceProjection(front: true, openness: isExpanded ? 1 : 0))
                }
            }
        }
        .animation(reduceMotion ? nil : CrestMotion.collection, value: isExpanded)
    }

    private var faceColor: Color {
        color.color
    }
}

private struct BrowserFolderFaceProjection: GeometryEffect {
    let front: Bool
    var openness: Double
    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var transform = CATransform3DIdentity
        transform.m34 = BrowserFolderGeometry.perspective
        transform = CATransform3DTranslate(transform, BrowserFolderGeometry.translation * openness, 0, 0)
        transform = CATransform3DRotate(transform, BrowserFolderGeometry.yAngle * .pi / 180 * openness, 0, 1, 0)
        transform = CATransform3DRotate(
            transform,
            (front ? BrowserFolderGeometry.frontAngle : BrowserFolderGeometry.backAngle) * .pi / 180 * openness, 1, 0, 0
        )
        return ProjectionTransform(CGAffineTransform(translationX: 0, y: -size.height))
            .concatenating(ProjectionTransform(transform))
            .concatenating(ProjectionTransform(CGAffineTransform(translationX: 0, y: size.height)))
    }
}
