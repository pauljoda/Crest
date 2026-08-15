import SwiftUI

struct BrowserOnboardingPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: CrestRadius.card,
            style: .continuous
        )
        return
            content
            .background(CrestBrandTheme.canvas, in: shape)
            .overlay {
                shape.strokeBorder(
                    CrestBrandTheme.line,
                    lineWidth: CrestLayout.hairline
                )
            }
    }
}

#Preview("Onboarding Panel") {
    Text("Set up your browser")
        .padding()
        .modifier(BrowserOnboardingPanelModifier())
        .padding()
}
