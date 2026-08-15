import SwiftUI

struct BrowserNavigationFailureStatusIcon: View {
    let symbolName: String
    let accent: Color
    let iconSize: CGFloat

    var body: some View {
        Image(systemName: symbolName)
            .font(
                .system(
                    size: iconSize * BrowserNavigationFailureMetrics.iconSymbolScale,
                    weight: .semibold
                )
            )
            .foregroundStyle(accent)
            .frame(width: iconSize, height: iconSize)
            .background(
                accent.opacity(BrowserNavigationFailureMetrics.iconBackgroundOpacity),
                in: .rect(
                    cornerRadius: iconSize
                        * BrowserNavigationFailureMetrics.iconCornerScale
                )
            )
            .accessibilityHidden(true)
    }
}

#Preview("Navigation Failure Status Icon") {
    BrowserNavigationFailureStatusIcon(
        symbolName: "wifi.slash",
        accent: .blue,
        iconSize: BrowserNavigationFailureMetrics.iconSize
    )
    .padding()
}
