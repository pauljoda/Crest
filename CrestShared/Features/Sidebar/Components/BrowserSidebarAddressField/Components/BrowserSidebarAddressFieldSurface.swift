import SwiftUI

/// The address field's own surface: the band it occupies, the tint that fills
/// from the leading edge as a page loads, and the ring that says it is being
/// edited.
///
/// It is a modifier rather than a container because the sidebar field is not
/// its only wearer — the Quick Window dresses its own address row in the same
/// surface without adopting the sidebar's anatomy.
struct BrowserSidebarAddressFieldSurface: ViewModifier {
    var metrics = BrowserSidebarAddressFieldMetrics.pointer
    var leadingPadding: CGFloat? = nil
    let progress: Double
    let isLoading: Bool
    let isEditing: Bool
    var branding: SpaceBranding? = nil
    /// Whether the field stands on Liquid Glass, as the command palette it
    /// grows into does, rather than the device's surface material.
    var isGlass = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Environment(\.spaceChromeAccent) private var spaceAccent

    func body(content: Content) -> some View {
        band(
            content
                .padding(.leading, leadingPadding ?? metrics.horizontalPadding)
                .padding(.trailing, metrics.horizontalPadding)
        )
        .background {
            ZStack(alignment: .leading) {
                if !isGlass {
                    CrestSurfaceLayer(shape: fieldShape)
                }
                if !reduceTransparency {
                    fieldShape.fill(accent.opacity(BrowserTabAppearance.intensity(appearance.fill) * 0.4))
                }
                fieldShape
                    .fill(accent.opacity(isLoading ? BrowserSidebarAddressFieldMetrics.loadingFillOpacity : 0))
                    .scaleEffect(x: loadingProgress, anchor: .leading)
                    .mask(fieldShape)
                    .animation(
                        CrestMotion.loadingProgress.unlessReducingMotion(reduceMotion),
                        value: loadingProgress
                    )
            }
        }
        .modifier(GlassLayer(isGlass: isGlass, shape: fieldShape, reduceTransparency: reduceTransparency))
        .overlay {
            fieldShape
                .strokeBorder(
                    isEditing
                        ? (appearance.usesAccentWhenEditing ? accent : metrics.editingRingColor)
                        : accent.opacity(BrowserTabAppearance.intensity(appearance.border)),
                    lineWidth: appearance.border > 0 || appearance.usesAccentWhenEditing
                        ? max(1, metrics.editingRingWidth) : metrics.editingRingWidth,
                    antialiased: true
                )
        }
    }

    @ViewBuilder
    private func band(_ content: some View) -> some View {
        if metrics.growsWithContent {
            content.frame(minHeight: metrics.height)
        } else {
            content.frame(height: metrics.height)
        }
    }

    private var loadingProgress: CGFloat {
        BrowserPageSurfacePresentation.loadingProgress(
            estimatedProgress: progress,
            isNavigating: isLoading
        )
    }

    private var appearance: BrowserAddressAppearance { BrowserDeviceAppearanceStore.shared.address }
    private var accent: Color {
        appearance.color?.color ?? spaceAccent ?? (branding?.primaryColor ?? .indigo).color
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)
    }

    /// The command palette's own glass under a field that stands on it.
    private struct GlassLayer: ViewModifier {
        let isGlass: Bool
        let shape: RoundedRectangle
        let reduceTransparency: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if isGlass {
                content.modifier(
                    BrowserCommandPaletteShellMaterial(shape: shape, reduceTransparency: reduceTransparency))
            } else {
                content
            }
        }
    }
}

extension View {
    func browserAddressFieldSurface(
        metrics: BrowserSidebarAddressFieldMetrics = .pointer,
        leadingPadding: CGFloat? = nil,
        progress: Double,
        isLoading: Bool,
        isEditing: Bool,
        branding: SpaceBranding? = nil,
        isGlass: Bool = false
    ) -> some View {
        modifier(
            BrowserSidebarAddressFieldSurface(
                metrics: metrics,
                leadingPadding: leadingPadding,
                progress: progress,
                isLoading: isLoading,
                isEditing: isEditing,
                branding: branding,
                isGlass: isGlass
            )
        )
    }
}
