import SwiftUI

/// Opens a tab using the hosting sidebar’s input and density preferences.
struct BrowserNewTabRow: View {
    let capabilities: BrowserInteractionCapabilities
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0

    private var tabMetrics: BrowserSidebarTabRowMetrics {
        BrowserSidebarInteractionPolicy.tabRowMetrics(capabilities)
    }

    private var metrics: BrowserSidebarNewTabRowMetrics {
        BrowserSidebarInteractionPolicy.newTabRowMetrics(capabilities)
    }

    private var rowHeight: CGFloat {
        let base = BrowserSidebarInteractionPolicy.rowMinHeight(
            capabilities,
            dynamicTypeSize: dynamicTypeSize
        )
        return BrowserSidebarDensityPolicy.rowHeight(
            base: base, scale: dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale,
            touch: capabilities.supportsTouch)
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text("New Tab")
                    .modifier(BrowserSidebarDensityFont(scale: tabScale, supportsTouch: capabilities.supportsTouch))
                    .lineLimit(1)
            } icon: {
                Image(systemName: "plus")
                    .font(tabMetrics.faviconSlot.map { .system(size: $0.glyphSize, weight: $0.glyphWeight) })
                    .frame(width: tabMetrics.faviconSlot?.width ?? 18)
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, metrics.labelHorizontalInset)
            .frame(minHeight: rowHeight, maxHeight: metrics.usesFixedHeight ? rowHeight : nil)
            .frame(
                maxWidth: .infinity,
                maxHeight: metrics.usesFixedHeight ? .infinity : nil,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New Tab")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityIdentifier("new-tab")
        .foregroundStyle(.secondary)
        .modifier(BrowserNewTabRowSurface(metrics: metrics))
        .padding(
            .vertical,
            BrowserSidebarDensityPolicy.rowSeparation(
                scale: tabScale, hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all) / 2
        )
        .padding(.horizontal, metrics.rowHorizontalInset)
        .modifier(BrowserNewTabRowTooltip(metrics: metrics))
    }
}

private struct BrowserNewTabRowSurface: ViewModifier {
    let metrics: BrowserSidebarNewTabRowMetrics

    @ViewBuilder
    func body(content: Content) -> some View {
        if metrics.showsHoverSurface {
            content.crestHoverSurface(
                cornerRadius: CrestLayout.sidebarControlCornerRadius
            )
        } else {
            content
        }
    }
}

private struct BrowserNewTabRowTooltip: ViewModifier {
    let metrics: BrowserSidebarNewTabRowMetrics

    @ViewBuilder
    func body(content: Content) -> some View {
        if metrics.showsShortcutTooltip {
            content.help("New Tab (⌘T)")
        } else {
            content
        }
    }
}
