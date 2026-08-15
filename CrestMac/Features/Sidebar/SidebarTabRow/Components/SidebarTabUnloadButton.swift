import SwiftUI

struct SidebarTabUnloadButton: View {
    let configuration: SidebarTabRowConfiguration
    let unload: (TabID) -> Void
    let isVisible: Bool

    var body: some View {
        Button {
            guard configuration.isCurrentAndUnlocked else { return }
            unload(configuration.tab.id)
        } label: {
            SidebarTabTrailingControlLabel(systemName: "minus")
        }
        .buttonStyle(controlStyle)
        .contentShape(.rect)
        .opacity(isVisible ? 1 : 0)
        .disabled(!configuration.isLoaded || !configuration.isCurrentAndUnlocked)
        .allowsHitTesting(isVisible)
        .accessibilityLabel("Unload \(configuration.tab.displayTitle)")
        .help("Unload Tab")
    }

    private var controlStyle: CrestChromeButtonStyle {
        CrestChromeButtonStyle(controlSize: BrowserTabTrailingControlPolicy.size)
    }
}

#Preview {
    SidebarTabUnloadButton(
        configuration: SidebarTabRowPreviewFixture.configuration(
            placement: .saved
        ),
        unload: { _ in },
        isVisible: true
    )
    .padding()
}
