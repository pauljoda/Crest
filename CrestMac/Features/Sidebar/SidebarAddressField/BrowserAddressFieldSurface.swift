import SwiftUI

struct BrowserAddressFieldSurface: ViewModifier {
    let progress: Double
    let isLoading: Bool
    let isEditing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .frame(height: BrowserChromeLayout.addressHeight)
            .background {
                ZStack(alignment: .leading) {
                    fieldShape.fill(CrestColor.chromeSurface)
                    fieldShape
                        .fill(.tint.opacity(isLoading ? 0.2 : 0))
                        .scaleEffect(x: loadingProgress, anchor: .leading)
                        .mask(fieldShape)
                        .animation(
                            BrowserVisualAccessibilityPolicy.animation(
                                CrestMotion.loadingProgress,
                                reduceMotion: reduceMotion
                            ),
                            value: loadingProgress
                        )
                }
            }
            .overlay {
                fieldShape
                    .strokeBorder(
                        CrestColor.selectedBorder.opacity(isEditing ? 1 : 0),
                        lineWidth: BrowserChromeLayout.addressEditingRingWidth,
                        antialiased: true
                    )
            }
    }

    private var loadingProgress: CGFloat {
        isLoading ? CGFloat(min(max(progress, 0.04), 1)) : 0
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: BrowserChromeLayout.addressCornerRadius,
            style: .continuous
        )
    }
}

extension View {
    func browserAddressFieldSurface(
        progress: Double,
        isLoading: Bool,
        isEditing: Bool
    ) -> some View {
        modifier(
            BrowserAddressFieldSurface(
                progress: progress,
                isLoading: isLoading,
                isEditing: isEditing
            )
        )
    }
}
