import SwiftUI

struct MobileSpacePrivateBrowsingButton: View {
    let isPrivateBrowsing: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MobileSpaceUtilityButtonLabel(
                systemImage: BrowserPrivateBrowsingAppearance.symbol
            )
        }
        .foregroundStyle(isPrivateBrowsing ? accentColor : Color.primary)
        .accessibilityLabel(
            isPrivateBrowsing ? "Leave Private Browsing" : "Private Browsing"
        )
        .accessibilityValue(isPrivateBrowsing ? "On" : "Off")
        .accessibilityIdentifier("private-browsing-toggle")
    }
}

#Preview("Private Browsing Button", traits: .sizeThatFitsLayout) {
    MobileSpacePrivateBrowsingButton(
        isPrivateBrowsing: true,
        accentColor: .indigo,
        action: {}
    )
    .buttonStyle(.plain)
    .padding()
}
