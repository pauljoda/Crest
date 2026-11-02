import SwiftUI

/// The surface of every flyout Crest draws over its windows, such as Site
/// Controls or a permission request: one dark surface whose labels are read in
/// that same appearance, so neither the Space's ink, the window's appearance
/// nor the page behind the flyout can put light labels on a light background.
///
/// The material is a solid one of its own rather than the device's surface
/// choice: that choice suits layers on the sidebar, but a see-through one lets
/// a bright page show through a flyout held over it.
struct CrestFlyoutStyle: ViewModifier {
    // MARK: - Static Variables

    private static let material = CrestSurfaceMaterial.thick

    // MARK: - Variables

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .tint(CrestBrandTheme.accent(.dark))
            .environment(\.colorScheme, .dark)
            .presentationBackground {
                Rectangle()
                    .fill(Self.material.material)
                    .environment(\.colorScheme, .dark)
            }
            .preferredColorScheme(.dark)
    }
}

extension View {
    /// Draws this flyout's content on Crest's flyout surface.
    func crestFlyoutStyle() -> some View {
        modifier(CrestFlyoutStyle())
    }
}

#if DEBUG
    #Preview("Flyout from a light Space") {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text(verbatim: "example.com").font(.headline)
            Text(verbatim: "Wants to use your camera").foregroundStyle(.secondary)
            HStack {
                Button("Deny") {}.buttonStyle(.bordered)
                Button("Allow") {}.buttonStyle(.borderedProminent)
            }
        }
        .padding(CrestSpacing.medium)
        .crestFlyoutStyle()
        .background { Rectangle().fill(CrestSurfaceMaterial.thick.material).environment(\.colorScheme, .dark) }
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
        .padding()
        .background(Color.white)
    }
#endif
