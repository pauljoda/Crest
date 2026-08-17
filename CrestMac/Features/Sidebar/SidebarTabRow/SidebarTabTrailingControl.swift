import SwiftUI

struct SidebarTabTrailingControl: View {
    let configuration: SidebarTabRowConfiguration
    let isHovering: Bool

    @ViewBuilder
    var body: some View {
        if configuration.tab.placement == .saved,
            let unload = configuration.unload
        {
            SidebarTabUnloadButton(
                configuration: configuration,
                unload: unload,
                isVisible: configuration.isLoaded
                    && (isHovering || configuration.isSelected)
            )
        } else {
            SidebarTabCloseButton(
                configuration: configuration,
                isVisible: configuration.canClose
                    && (isHovering || configuration.isSelected)
            )
        }
    }
}

private struct SidebarTabCloseButton: View {
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

private struct SidebarTabUnloadButton: View {
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

private struct SidebarTabTrailingControlLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(
                .system(
                    size: BrowserTabTrailingControlPolicy.glyphSize,
                    weight: .regular
                )
            )
            .frame(
                width: BrowserTabTrailingControlPolicy.minimumHitTarget,
                height: BrowserTabTrailingControlPolicy.minimumHitTarget
            )
            .contentShape(.rect)
    }
}
