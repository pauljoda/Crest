import SwiftUI

struct MobileCredentialPromptSurface<Content: View>: View {
    let accessibilityLabel: LocalizedStringKey
    let accessibilityIdentifier: String
    let content: Content

    init(
        accessibilityLabel: LocalizedStringKey,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                BrowserAccessibleMaterialBackground(
                    material: .regular,
                    shape: Rectangle()
                )
            }
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
