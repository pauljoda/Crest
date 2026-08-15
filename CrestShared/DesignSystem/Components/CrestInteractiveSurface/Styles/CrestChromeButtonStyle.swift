import SwiftUI

/// Shared hover and press treatment for compact browser chrome controls.
struct CrestChromeButtonStyle: ButtonStyle {
    var controlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var cornerRadius = CrestLayout.sidebarControlCornerRadius

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(
                CrestChromeButtonSurface(
                    isPressed: configuration.isPressed,
                    controlSize: controlSize,
                    cornerRadius: cornerRadius
                )
            )
    }
}

#Preview("Chrome Button") {
    Button("Reload", systemImage: "arrow.clockwise") {}
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle())
        .padding()
}
