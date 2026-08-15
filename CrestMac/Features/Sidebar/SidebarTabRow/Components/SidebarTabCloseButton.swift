import SwiftUI

struct SidebarTabCloseButton: View {
    let configuration: SidebarTabRowConfiguration
    let isVisible: Bool

    var body: some View {
        Button {
            guard configuration.isCurrentAndUnlocked else { return }
            configuration.browser.closeTab(
                configuration.tab.id,
                matching: configuration.assignment
            )
        } label: {
            SidebarTabTrailingControlLabel(systemName: "xmark")
        }
        .buttonStyle(controlStyle)
        .contentShape(.rect)
        .foregroundStyle(BrowserVisualAccessibilityPolicy.tabCloseForeground)
        .opacity(isVisible ? 1 : 0)
        .disabled(!configuration.canClose || !configuration.isCurrentAndUnlocked)
        .allowsHitTesting(isVisible)
        .accessibilityLabel("Close \(configuration.tab.displayTitle)")
    }

    private var controlStyle: CrestChromeButtonStyle {
        CrestChromeButtonStyle(controlSize: BrowserTabTrailingControlPolicy.size)
    }
}

#Preview {
    SidebarTabCloseButton(
        configuration: SidebarTabRowPreviewFixture.configuration(),
        isVisible: true
    )
    .padding()
}
