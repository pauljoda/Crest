import SwiftUI

struct BrowserSiteControlTrigger: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(
                    .system(
                        size: BrowserTabTrailingControlPolicy.glyphSize,
                        weight: .medium
                    )
                )
                .frame(
                    width: BrowserSiteControlLayoutPolicy.triggerSize.width,
                    height: BrowserSiteControlLayoutPolicy.triggerSize.height
                )
                .contentShape(.rect)
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: BrowserSiteControlLayoutPolicy.triggerSize
            )
        )
        .foregroundStyle(.secondary)
        .accessibilityLabel("Site Controls")
        .accessibilityIdentifier("browser-site-controls")
        .help("Site Controls")
    }
}
