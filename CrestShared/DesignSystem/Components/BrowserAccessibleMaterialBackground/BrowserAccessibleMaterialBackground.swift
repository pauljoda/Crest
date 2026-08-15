import SwiftUI

/// Supplies an opaque semantic background when Reduce Transparency is on and
/// preserves the requested material everywhere else.
struct BrowserAccessibleMaterialBackground<BackgroundShape: Shape>: View {
    let material: Material
    let shape: BackgroundShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            shape.fill(CrestPlatformAccessibleSurfaceColor.background)
        } else {
            shape.fill(material)
        }
    }
}

#Preview("Accessible Material") {
    Text("Accessible Material")
        .padding(CrestSpacing.extraExtraLarge)
        .background {
            BrowserAccessibleMaterialBackground(
                material: .regularMaterial,
                shape: RoundedRectangle(
                    cornerRadius: CrestRadius.card,
                    style: .continuous
                )
            )
        }
        .padding(CrestSpacing.large)
}
