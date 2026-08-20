import SwiftUI

/// The row that opens a new tab, at the head of the current run, on every
/// shell.
///
/// One row rather than two resemblances: what differs between a pointer shell
/// and a touch one — where the insets sit, whether the height is exact, whether
/// a hover surface and a shortcut tooltip exist at all — is read from
/// `BrowserSidebarInteractionPolicy` instead of from which target compiled the
/// file.
struct BrowserNewTabRow: View {
    let capabilities: BrowserInteractionCapabilities
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metrics: BrowserSidebarNewTabRowMetrics {
        BrowserSidebarInteractionPolicy.newTabRowMetrics(capabilities)
    }

    /// The height the row rests at. A shell that holds one exact height pins
    /// both ends of the frame to it; a shell that lets the row grow pins only
    /// the floor.
    private var rowHeight: CGFloat {
        BrowserSidebarInteractionPolicy.rowMinHeight(
            capabilities,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    var body: some View {
        Button(action: action) {
            Label("New Tab", systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, metrics.labelHorizontalInset)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: metrics.usesFixedHeight ? .infinity : nil,
                    alignment: .leading
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(
            minHeight: rowHeight,
            maxHeight: metrics.usesFixedHeight ? rowHeight : nil
        )
        .modifier(BrowserNewTabRowSurface(metrics: metrics))
        .padding(.horizontal, metrics.rowHorizontalInset)
        .modifier(BrowserNewTabRowTooltip(metrics: metrics))
        .accessibilityIdentifier("new-tab")
    }
}

/// The treatment a pointer resting over the row earns it. A touch shell has
/// nothing to respond to, so the row is drawn plain there.
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

/// The shortcut the row names while a pointer rests on it, where both a pointer
/// and the keyboard it belongs to exist.
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
