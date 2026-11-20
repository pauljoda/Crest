import SwiftUI

/// The surface of every flyout Crest draws over its windows, such as Site
/// Controls, a color picker, a permission request or a password prompt:
/// Crest's opaque flyout color in the appearance Crest's windows have,
/// paper under ink in the light and charcoal under paper in the dark, so
/// neither the Space's ink, a scheme the presenting view forces nor the page
/// behind the flyout can put light labels on a light background.
///
/// The color is opaque rather than the device's surface material: that
/// material suits layers on the sidebar, but even the thickest one lets a
/// bright page show through a flyout held over it, and the labels must read
/// against the surface alone.
///
/// A presented flyout, such as a popover, gets its surface from its
/// presentation. A flyout laid over the page inside the window draws it in
/// its own shape, and leaves the window's appearance alone. One that floats
/// over the page on its own, such as a notice or a hover preview, is
/// outlined just inside its edge in Crest's hairline, so it stands apart
/// from a page as pale or as dark as the surface.
struct CrestFlyoutStyle: ViewModifier {
    // MARK: - Static Variables

    fileprivate static let outlineWidth: CGFloat = 0.5

    // MARK: - Variables

    /// The shape an in-window flyout's surface fills, or nil for a presented
    /// flyout, whose presentation fills its own.
    let inWindowShape: AnyShape?
    /// The line a floating flyout draws its outline along, or nil for a
    /// flyout that has none.
    var outline: AnyShape?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme

    /// The appearance Crest's windows have, whatever a Space or the
    /// presenting view sets around the flyout.
    private var scheme: ColorScheme { deviceColorScheme ?? colorScheme }

    @ViewBuilder
    func body(content: Content) -> some View {
        let scheme = scheme
        let labels =
            content
            .foregroundStyle(CrestBrandTheme.textDisplay(scheme))
            .tint(CrestBrandTheme.accent(scheme))
            .environment(\.colorScheme, scheme)
        if let inWindowShape {
            labels
                .background { Self.surface(in: inWindowShape, scheme: scheme) }
                .overlay {
                    if let outline {
                        outline
                            .stroke(CrestBrandTheme.line(scheme), lineWidth: Self.outlineWidth)
                            .allowsHitTesting(false)
                    }
                }
        } else {
            labels
                .presentationBackground { Self.surface(in: Rectangle(), scheme: scheme) }
                .preferredColorScheme(scheme)
        }
    }

    // MARK: - Actions - Drawing

    private static func surface(in shape: some Shape, scheme: ColorScheme) -> some View {
        shape
            .fill(CrestBrandTheme.flyout)
            .environment(\.colorScheme, scheme)
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

    /// Draws this card, floating over the page inside the window on its own,
    /// such as a notice, a hover preview or a bar over the page, on Crest's
    /// flyout surface in `shape`, outlined just inside its edge.
    func crestFloatingFlyoutStyle(in shape: some InsettableShape) -> some View {
        modifier(
            CrestFlyoutStyle(
                inWindowShape: AnyShape(shape),
                outline: AnyShape(shape.inset(by: CrestFlyoutStyle.outlineWidth / 2))))
    }
}

#if DEBUG
    #Preview("Flyout from a dark Space") {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text(verbatim: "example.com").font(.headline)
            Text(verbatim: "Wants to use your camera").foregroundStyle(.secondary)
            HStack {
                Button("Deny") {}.buttonStyle(.crestSecondary)
                Button("Allow") {}.buttonStyle(.crestPrimary)
            }
        }
        .padding(CrestSpacing.medium)
        .crestFlyoutStyle(in: .rect(cornerRadius: CrestRadius.compact))
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
        .environment(\.deviceColorScheme, .light)
        .padding()
        .background(Color.black)
    }
#endif
