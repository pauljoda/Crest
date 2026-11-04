import SwiftUI

/// The surface of every flyout Crest draws over its windows, such as Site
/// Controls, a color picker or a permission request: one solid dark surface
/// whose labels are read in that same appearance, so neither the Space's ink,
/// a scheme the presenting view forces, the window's appearance nor the page
/// behind the flyout can put light labels on a light background.
///
/// The material is one of its own rather than the device's surface choice,
/// laid over the window's own background: that choice suits layers on the
/// sidebar, but even the thickest material lets a bright page show through a
/// flyout held over it, and the labels must read against the surface alone.
struct CrestFlyoutStyle: ViewModifier {
    // MARK: - Static Variables

    private static let colorScheme = ColorScheme.dark
    private static let material = CrestSurfaceMaterial.thick

    // MARK: - Variables

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .tint(CrestBrandTheme.accent(Self.colorScheme))
            .environment(\.colorScheme, Self.colorScheme)
            .presentationBackground {
                Rectangle()
                    .fill(CrestColor.windowBackground)
                    .overlay { Rectangle().fill(Self.material.material) }
                    .environment(\.colorScheme, Self.colorScheme)
            }
            .preferredColorScheme(Self.colorScheme)
    }
}

extension View {
    /// Draws this flyout's content on Crest's flyout surface. A popover gets
    /// it from ``crestPopover(isPresented:attachmentAnchor:arrowEdge:content:)``.
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
