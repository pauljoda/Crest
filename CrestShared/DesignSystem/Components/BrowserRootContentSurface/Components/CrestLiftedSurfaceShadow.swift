import SwiftUI

/// A transparent SwiftUI canvas that casts only the exterior part of a rounded
/// surface's shadow.
struct CrestLiftedSurfaceShadow: View {
    let cornerRadius: CGFloat
    let opacity: Double
    let radius: CGFloat
    let yOffset: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let drawingOutset = BrowserPageSurfacePolicy.shadowDrawingOutset

        Canvas { context, size in
            guard !reduceTransparency, opacity > 0 else { return }

            let bounds = CGRect(
                x: drawingOutset,
                y: drawingOutset,
                width: max(0, size.width - drawingOutset * 2),
                height: max(0, size.height - drawingOutset * 2)
            )
            let path = RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            ).path(in: bounds)

            context.drawLayer { shadowContext in
                shadowContext.addFilter(
                    .shadow(
                        color: .black.opacity(opacity),
                        radius: radius,
                        x: 0,
                        y: yOffset,
                        options: .shadowOnly
                    )
                )
                shadowContext.fill(path, with: .color(.black))
            }

            context.blendMode = .destinationOut
            context.fill(path, with: .color(.white))
        }
        .padding(-drawingOutset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Lifted Surface Shadow") {
    CrestLiftedSurfaceShadow(
        cornerRadius: CrestRadius.card,
        opacity: BrowserPageSurfacePolicy.shadowOpacity,
        radius: BrowserPageSurfacePolicy.shadowRadius,
        yOffset: BrowserPageSurfacePolicy.shadowYOffset
    )
    .frame(width: 320, height: 180)
    .padding(CrestSpacing.extraExtraLarge)
}
