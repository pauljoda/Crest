import SwiftUI

/// The stable root-level frame around browser content. Page states only choose
/// whether their interior is opaque; clipping, the theme seam, and elevation
/// remain owned here.
struct BrowserRootContentSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let seamWidth: CGFloat
    let frameInsets: EdgeInsets
    let usesTransparentInnerSurface: Bool
    let showsFallbackBorder: Bool
    let content: Content

    init(
        cornerRadius: CGFloat,
        seamWidth: CGFloat,
        frameInsets: EdgeInsets,
        usesTransparentInnerSurface: Bool,
        showsFallbackBorder: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.seamWidth = seamWidth
        self.frameInsets = frameInsets
        self.usesTransparentInnerSurface = usesTransparentInnerSurface
        self.showsFallbackBorder = showsFallbackBorder
        self.content = content()
    }

    var body: some View {
        let outerShape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        content
            .background {
                if usesTransparentInnerSurface {
                    Color.clear
                } else {
                    Rectangle().fill(.background)
                }
            }
            .clipShape(
                .rect(
                    cornerRadius: max(0, cornerRadius - seamWidth),
                    style: .continuous
                )
            )
            .padding(seamWidth)
            .clipShape(outerShape, style: FillStyle(antialiased: true))
            .background {
                CrestLiftedSurfaceShadow(
                    cornerRadius: cornerRadius,
                    opacity: BrowserPageSurfacePolicy.shadowOpacity,
                    radius: BrowserPageSurfacePolicy.shadowRadius,
                    yOffset: BrowserPageSurfacePolicy.shadowYOffset
                )
            }
            .overlay {
                outerShape
                    .strokeBorder(
                        Color.black.opacity(
                            showsFallbackBorder
                                ? CrestOpacity.border
                                : BrowserPageSurfacePolicy.boundaryStrokeOpacity
                        ),
                        lineWidth: BrowserPageSurfacePolicy.boundaryStrokeWidth,
                        antialiased: true
                    )
                    .allowsHitTesting(false)
            }
            .padding(frameInsets)
    }
}

#Preview("Root Content Surface") {
    ZStack {
        CrestBrandTheme.canvas
        BrowserRootContentSurface(
            cornerRadius: CrestRadius.card,
            seamWidth: CrestLayout.hairline,
            frameInsets: EdgeInsets(
                top: CrestSpacing.large,
                leading: CrestSpacing.large,
                bottom: CrestSpacing.large,
                trailing: CrestSpacing.large
            ),
            usesTransparentInnerSurface: false
        ) {
            Label("Loaded Page", systemImage: "globe")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    .frame(width: 420, height: 280)
}
