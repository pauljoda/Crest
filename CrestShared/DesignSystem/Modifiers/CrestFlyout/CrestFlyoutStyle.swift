import SwiftUI

/// The surface of every flyout Crest draws over its windows, such as Site
/// Controls, a color picker, a permission request or a password prompt: one
/// solid dark surface whose labels are read in that same appearance, so
/// neither the Space's ink, a scheme the presenting view forces, the window's
/// appearance nor the page behind the flyout can put light labels on a light
/// background.
///
/// The material is one of its own rather than the device's surface choice,
/// laid over the window's own background: that choice suits layers on the
/// sidebar, but even the thickest material lets a bright page show through a
/// flyout held over it, and the labels must read against the surface alone.
///
/// A presented flyout, such as a popover, gets its surface from its
/// presentation. A flyout laid over the page inside the window draws it in
/// its own shape, and leaves the window's appearance alone.
struct CrestFlyoutStyle: ViewModifier {
    // MARK: - Static Variables

    private static let colorScheme = ColorScheme.dark
    private static let material = CrestSurfaceMaterial.thick

    // MARK: - Variables

    /// The shape an in-window flyout's surface fills, or nil for a presented
    /// flyout, whose presentation fills its own.
    let inWindowShape: AnyShape?

    @ViewBuilder
    func body(content: Content) -> some View {
        let labels =
            content
            .foregroundStyle(.primary)
            .tint(CrestBrandTheme.accent(Self.colorScheme))
            .environment(\.colorScheme, Self.colorScheme)
        if let inWindowShape {
            labels.background { Self.surface(in: inWindowShape) }
        } else {
            labels
                .presentationBackground { Self.surface(in: Rectangle()) }
                .preferredColorScheme(Self.colorScheme)
        }
    }

    // MARK: - Actions - Drawing

    private static func surface(in shape: some Shape) -> some View {
        shape
            .fill(CrestColor.windowBackground)
            .overlay { shape.fill(material.material) }
            .environment(\.colorScheme, colorScheme)
    }
}

extension View {
    /// Draws this presented flyout's content on Crest's flyout surface. A
    /// popover gets it from
    /// ``crestPopover(isPresented:attachmentAnchor:arrowEdge:content:)``.
    func crestFlyoutStyle() -> some View {
        modifier(CrestFlyoutStyle(inWindowShape: nil))
    }

    /// Draws this flyout, laid over the page inside the window, on Crest's
    /// flyout surface in `shape`. Apply it after an outline or divider the
    /// flyout draws, so they read in the surface's appearance too.
    func crestFlyoutStyle(in shape: some Shape) -> some View {
        modifier(CrestFlyoutStyle(inWindowShape: AnyShape(shape)))
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
        .crestFlyoutStyle(in: .rect(cornerRadius: CrestRadius.compact))
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
        .padding()
        .background(Color.white)
    }
#endif
