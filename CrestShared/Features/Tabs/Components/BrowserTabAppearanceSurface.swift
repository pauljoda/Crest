import SwiftUI

/// Appearance only; selection, promotion and drag owners remain on the row.
struct BrowserTabAppearanceSurface: ViewModifier {
    let appearance: BrowserTabAppearance
    let accent: Color
    let isPinned: Bool
    let isSelected: Bool
    let isHovering: Bool
    var selectionEmphasis = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let radius = BrowserDeviceAppearanceStore.shared.sidebarCornerRadius
        let selectedAccent = isPinned || appearance.outlinesSelectedTabs
        let showsBorder = appearance.borders == .all || (isPinned && appearance.borders == .pinned)
        let fill = BrowserTabAppearance.intensity(appearance.pinFill)
        let hover = BrowserTabAppearance.intensity(appearance.hoverFill)
        content
            .modifier(
                CrestInteractiveSurfaceModifier(
                    isSelected: isSelected, selectionEmphasis: selectionEmphasis,
                    isHovering: isHovering, cornerRadius: radius, isPressed: false,
                    showsRestingSurface: isPinned,
                    selectedBorderColor: selectedAccent ? accent : CrestColor.selectedBorder,
                    selectedBorderWidth: isPinned ? CrestLayout.pinnedAccentBorderWidth : 1,
                    customSelectedFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.5) : nil,
                    // Hover keeps its standard weight; the setting only decides how much of
                    // the accent is in it, from the neutral hover to the accent itself.
                    customHoverFill: hover > 0 && !reduceTransparency
                        ? Color.primary.mix(with: accent, by: hover).opacity(CrestOpacity.hover) : nil,
                    customRestingFill: isPinned && fill > 0 && !reduceTransparency ? accent.opacity(fill * 0.2) : nil,
                    restingBorderColor: showsBorder ? accent : .clear)
            )
            .background {
                if isSelected, appearance.pinGlow > 0, !reduceTransparency {
                    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                    GeometryReader { geometry in
                        let spread: CGFloat = 12
                        let tabBounds = CGRect(origin: CGPoint(x: spread, y: spread), size: geometry.size)
                        let canvasBounds = tabBounds.insetBy(dx: -spread, dy: -spread)
                        shape
                            .fill(accent.opacity(BrowserTabAppearance.intensity(appearance.pinGlow) * 0.6))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 5)
                            .padding(spread)
                            .mask {
                                Path { path in
                                    path.addRect(canvasBounds)
                                    path.addPath(shape.path(in: tabBounds))
                                }
                                .fill(style: FillStyle(eoFill: true))
                            }
                            .offset(x: -spread, y: -spread)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}
