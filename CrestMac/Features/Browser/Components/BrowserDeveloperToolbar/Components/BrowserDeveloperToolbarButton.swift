import SwiftUI

struct BrowserDeveloperToolbarButton: View {
    let label: LocalizedStringKey
    let systemImage: String
    var isActive = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(
                    width: BrowserDeveloperToolbarMetrics.buttonSize,
                    height: BrowserDeveloperToolbarMetrics.buttonSize
                )
                .contentShape(.rect)
        }
        .buttonStyle(BrowserDeveloperToolbarButtonStyle(isActive: isActive))
        .accessibilityLabel(Text(label))
        .help(Text(label))
    }
}

#Preview("Developer Toolbar Button") {
    BrowserDeveloperToolbarButton(
        label: "Inspect Element",
        systemImage: "scope",
        isActive: true,
        action: {}
    )
    .padding()
}
