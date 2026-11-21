import SwiftUI

/// Geometry shared by selected, pressed, and hovered browser surfaces.
enum CrestInteractiveSurfaceMetrics {
    static let defaultSelectedBorderWidth: CGFloat = 0.5
    static let increasedContrastBorderWidth: CGFloat = 1.5
    static let selectedShadowRadius: CGFloat = 2
    static let selectedShadowYOffset: CGFloat = 1
    /// The shadow a selection on paper casts, lying flat on the layer under
    /// it, as setup's paper chips do.
    static let paperShadowRadius: CGFloat = 1.5
    static let paperShadowYOffset: CGFloat = 1
}

struct CrestInteractiveSurfaceModifier: ViewModifier {
    let isSelected: Bool
    var selectionEmphasis = false
    let isHovering: Bool
    let cornerRadius: CGFloat
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat
    var customSelectedFill: Color? = nil
    var customHoverFill: Color? = nil
    var customRestingFill: Color? = nil
    var restingBorderColor: Color = .clear
    /// The sheet of Crest's light paper a selected or pressed surface is,
    /// casting the paper's shadow, or nil for a layer of the device's
    /// material.
    var selectionPaper: CrestPaperSheet? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.deviceColorScheme) private var deviceColorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let isEmphasized = isSelected || isPressed

        content
            .background {
                surface(in: shape)
                    .overlay { if selectionEmphasis { shape.fill(CrestColor.hover) } }
            }
            .overlay {
                shape
                    .strokeBorder(
                        isEmphasized ? selectedBorderColor : restingBorderColor,
                        lineWidth: borderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadowColor.opacity(shadowOpacity),
                radius: isEmphasized ? shadowRadius : 0,
                y: isEmphasized ? shadowYOffset : 0
            )
            .animation(accessibleSurfaceAnimation, value: isHovering)
            .animation(accessibleSurfaceAnimation, value: selectionEmphasis)
            // Selection shows at once, as browsers switch tabs; only a press
            // eases in. Fading a selected surface in and out redraws its
            // shadow, its glow and the content it covers every frame, on two
            // surfaces at every tab switch.
            .animation(accessibleSurfaceAnimation, value: isPressed)
            // Content on the material reads in the material's scheme, and
            // on paper in the paper's.
            .environment(
                \.colorScheme,
                contentScheme
            )
    }

    /// Whether the surface draws the device's material under the content.
    private var showsMaterial: Bool { isSelected || isPressed || showsRestingSurface }

    /// The sheet of paper the surface is now, or nil where it is material.
    private var paper: CrestPaperSheet? { isSelected || isPressed ? selectionPaper : nil }

    /// Whether the surface is a sheet of paper now, rather than material.
    private var isPaper: Bool { paper != nil }

    /// The scheme content reads in: light on paper, the material's on the
    /// material, else the surroundings'.
    private var contentScheme: ColorScheme {
        if isPaper { return .light }
        return showsMaterial ? CrestSurfaceTone.shownScheme(over: colorScheme, window: deviceColorScheme) : colorScheme
    }

    /// Selected, pressed and resting surfaces are layers of the device's
    /// material, or a selection's sheet of paper, wearing their accent tint;
    /// hover is only ever a tint, laid over that layer or, on a plain row,
    /// alone.
    @ViewBuilder
    private func surface(in shape: RoundedRectangle) -> some View {
        if showsMaterial {
            CrestSurfaceLayer(
                shape: shape,
                tint: isSelected || isPressed ? customSelectedFill : customRestingFill,
                hoverTint: isHovering ? hoverFill : nil,
                paper: paper
            )
            .background {
                // Paper that lets light through lies over the surface as it
                // rests, in the scheme it rests in, unless it brings a ground
                // of its own.
                if showsRestingSurface, paper?.showsRestingSurface == true {
                    CrestSurfaceLayer(shape: shape, tint: customRestingFill)
                        .environment(\.colorScheme, colorScheme)
                }
            }
        } else if isHovering {
            shape.fill(hoverFill)
        }
    }

    private var hoverFill: Color { customHoverFill ?? CrestColor.hover }

    private var borderWidth: CGFloat {
        guard contrast == .increased else { return selectedBorderWidth }
        return max(
            CrestInteractiveSurfaceMetrics.increasedContrastBorderWidth,
            selectedBorderWidth
        )
    }

    private var shadowOpacity: Double {
        guard isSelected || isPressed, !reduceTransparency else { return 0 }
        return isPaper ? CrestOpacity.paperShadow : CrestOpacity.interactionSelectionShadow
    }

    private var shadowColor: Color { isPaper ? CrestBrandPalette.ink : .black }

    private var shadowRadius: CGFloat {
        isPaper ? CrestInteractiveSurfaceMetrics.paperShadowRadius : CrestInteractiveSurfaceMetrics.selectedShadowRadius
    }

    private var shadowYOffset: CGFloat {
        isPaper
            ? CrestInteractiveSurfaceMetrics.paperShadowYOffset : CrestInteractiveSurfaceMetrics.selectedShadowYOffset
    }

    private var accessibleSurfaceAnimation: Animation? {
        CrestMotion.surface.unlessReducingMotion(reduceMotion)
    }
}

/// Owns pointer hover state for controls that use Crest's shared interaction
/// surface but do not otherwise need to react to hover themselves.
private struct CrestHoverSurfaceModifier: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat
    let selectsOnPaper: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .modifier(
                CrestInteractiveSurfaceModifier(
                    isSelected: isSelected,
                    isHovering: isHovering && isEnabled,
                    cornerRadius: cornerRadius,
                    isPressed: isPressed && isEnabled,
                    showsRestingSurface: showsRestingSurface,
                    selectedBorderColor: selectedBorderColor,
                    selectedBorderWidth: selectedBorderWidth,
                    selectionPaper: selectsOnPaper ? .opaque : nil
                )
            )
            .onHover { isHovering = $0 }
    }
}

extension View {
    func crestInteractiveSurface(
        isSelected: Bool,
        isHovering: Bool,
        cornerRadius: CGFloat = CrestRadius.compact,
        selectionEmphasis: Bool = false,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = CrestColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            CrestInteractiveSurfaceMetrics.defaultSelectedBorderWidth
    ) -> some View {
        modifier(
            CrestInteractiveSurfaceModifier(
                isSelected: isSelected,
                selectionEmphasis: selectionEmphasis,
                isHovering: isHovering,
                cornerRadius: cornerRadius,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
        )
    }

    func crestHoverSurface(
        isSelected: Bool = false,
        cornerRadius: CGFloat = CrestRadius.compact,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = CrestColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            CrestInteractiveSurfaceMetrics.defaultSelectedBorderWidth,
        selectsOnPaper: Bool = false
    ) -> some View {
        modifier(
            CrestHoverSurfaceModifier(
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth,
                selectsOnPaper: selectsOnPaper
            )
        )
    }
}
