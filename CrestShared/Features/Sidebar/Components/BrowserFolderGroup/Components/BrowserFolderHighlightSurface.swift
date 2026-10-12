import SwiftUI

extension EnvironmentValues {
    @Entry var folderPreviewShowsHighlight = false
    @Entry var folderUsesContrastingForeground = false
    @Entry var folderBackgroundColor: BrandColor? = nil
}

/// Shared by live folder groups and the inline settings preview.
struct BrowserFolderHighlightSurface: ViewModifier {
    let color: BrandColor
    let intensity: Double
    var textColorMode: SpaceTextColorMode = .automatic
    var showsFill = true
    var showsBorders = true
    var leadingInset: CGFloat = CrestSpacing.small
    var isSelected = false
    var emphasisOpacity: Double = 0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.folderBackgroundColor) private var parentBackgroundColor

    private var foregroundScheme: ColorScheme {
        if let override = textColorMode.foregroundTone { return override == .light ? .dark : .light }
        guard showsFill, intensity > 0 else { return colorScheme }
        return compositedColor.foregroundTone.colorScheme
    }

    private var compositedColor: BrandColor {
        let channel = colorScheme == .dark ? 0.0 : 1.0
        return color.composited(
            opacity: fillOpacity,
            over: parentBackgroundColor ?? BrandColor(red: channel, green: channel, blue: channel))
    }

    private var fillOpacity: Double {
        let strength = intensity.isFinite ? min(max(intensity, 0), 1) : 0
        let baseline = reduceTransparency ? 0.28 : 0.12
        return baseline + (1 - baseline) * strength
    }

    func body(content: Content) -> some View {
        content
            .background {
                if showsFill {
                    RoundedRectangle(
                        cornerRadius: BrowserDeviceAppearanceStore.shared.containerCornerRadius(), style: .continuous
                    )
                    .fill(
                        color.color.opacity(fillOpacity)
                    )
                    .overlay {
                        if emphasisOpacity > 0 {
                            RoundedRectangle(
                                cornerRadius: BrowserDeviceAppearanceStore.shared.containerCornerRadius(),
                                style: .continuous
                            )
                            .fill(.primary.opacity(emphasisOpacity))
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(
                                cornerRadius: BrowserDeviceAppearanceStore.shared.containerCornerRadius(),
                                style: .continuous
                            )
                            .fill(CrestColor.hover)
                        }
                    }
                    .overlay {
                        if showsBorders {
                            RoundedRectangle(
                                cornerRadius: BrowserDeviceAppearanceStore.shared.containerCornerRadius(),
                                style: .continuous
                            )
                            .strokeBorder(color.color.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .padding(.leading, leadingInset)
                    .padding(.trailing, CrestSpacing.small)
                    .allowsHitTesting(false)
                }
            }
            .environment(\.colorScheme, foregroundScheme)
            .environment(\.folderUsesContrastingForeground, textColorMode != .automatic || showsFill)
            .environment(\.folderBackgroundColor, showsFill ? compositedColor : parentBackgroundColor)
    }
}
