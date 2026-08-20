import SwiftUI

/// The one control a tab row carries: close for a tab that belongs to the
/// session, unload for one that outlives it and only has a page to put away.
struct BrowserSidebarTabTrailingControl: View {
    let configuration: BrowserSidebarTabRowConfiguration
    let isHovering: Bool

    @ViewBuilder
    var body: some View {
        if configuration.tab.placement == .saved,
            let unload = configuration.unload
        {
            BrowserSidebarTabUnloadButton(
                configuration: configuration,
                unload: unload,
                isVisible: configuration.isLoaded && isRevealed
            )
        } else {
            BrowserSidebarTabCloseButton(
                configuration: configuration,
                isVisible: configuration.canClose && isRevealed
            )
        }
    }

    private var isRevealed: Bool {
        configuration.trailingControlMetrics.isRevealed(
            isHovering: isHovering,
            isSelected: configuration.isSelected
        )
    }
}

private struct BrowserSidebarTabCloseButton: View {
    let configuration: BrowserSidebarTabRowConfiguration
    let isVisible: Bool

    var body: some View {
        Button {
            guard configuration.isCurrentAndUnlocked else { return }
            configuration.browser.closeTab(
                configuration.tab.id,
                matching: configuration.assignment
            )
        } label: {
            BrowserSidebarTabTrailingControlLabel(
                systemName: "xmark",
                metrics: metrics
            )
        }
        .modifier(BrowserSidebarTabTrailingControlStyle(metrics: metrics))
        .contentShape(.rect)
        .foregroundStyle(BrowserVisualAccessibilityPolicy.tabCloseForeground)
        .opacity(
            isVisible
                ? metrics.closeOpacity(isSelected: configuration.isSelected)
                : 0
        )
        .disabled(!configuration.canClose || !configuration.isCurrentAndUnlocked)
        .allowsHitTesting(isVisible)
        .accessibilityLabel("Close \(configuration.tab.displayTitle)")
    }

    private var metrics: BrowserTabTrailingControlMetrics {
        configuration.trailingControlMetrics
    }
}

private struct BrowserSidebarTabUnloadButton: View {
    let configuration: BrowserSidebarTabRowConfiguration
    let unload: (TabID) -> Void
    let isVisible: Bool

    var body: some View {
        Button {
            guard configuration.isCurrentAndUnlocked else { return }
            unload(configuration.tab.id)
        } label: {
            BrowserSidebarTabTrailingControlLabel(
                systemName: "minus",
                metrics: metrics
            )
        }
        .modifier(BrowserSidebarTabTrailingControlStyle(metrics: metrics))
        .contentShape(.rect)
        .opacity(isVisible ? 1 : 0)
        .disabled(!configuration.isLoaded || !configuration.isCurrentAndUnlocked)
        .allowsHitTesting(isVisible)
        .accessibilityLabel("Unload \(configuration.tab.displayTitle)")
        .help("Unload Tab")
    }

    private var metrics: BrowserTabTrailingControlMetrics {
        configuration.trailingControlMetrics
    }
}

private struct BrowserSidebarTabTrailingControlLabel: View {
    let systemName: String
    let metrics: BrowserTabTrailingControlMetrics

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: metrics.glyphSize, weight: metrics.glyphWeight))
            .frame(
                width: metrics.controlSize.width,
                height: metrics.controlSize.height
            )
            .contentShape(.rect)
    }
}

/// The chrome's hover-and-press treatment where a pointer can earn it, and a
/// plain button where nothing can.
private struct BrowserSidebarTabTrailingControlStyle: ViewModifier {
    let metrics: BrowserTabTrailingControlMetrics

    @ViewBuilder
    func body(content: Content) -> some View {
        if metrics.usesChromeControlStyle {
            content.buttonStyle(
                CrestChromeButtonStyle(controlSize: metrics.controlSize)
            )
        } else {
            content.buttonStyle(.plain)
        }
    }
}
