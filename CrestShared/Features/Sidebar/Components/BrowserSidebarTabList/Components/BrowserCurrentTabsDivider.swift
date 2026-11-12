import SwiftUI

/// The seam between the saved run and the current one, on every shell.
///
/// Pointer-only shells reveal Clear on hover. Touch shells center its hit target
/// on the line, using the saved drop band as the space above it.
struct BrowserCurrentTabsDivider: View {
    /// The side of the clear control's hit target on a touch shell.
    private static var touchTarget: CGFloat { 44 }

    let capabilities: BrowserInteractionCapabilities
    var hasSavedTabsEndBand = false
    /// Whether the shell is currently in the state that reveals the control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    /// Whether there is anything left to clear.
    let canClear: Bool
    let clear: () -> Void
    /// How wide the clear control's label draws, which the line stops short
    /// of.
    @State private var clearLabelWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    private var metrics: BrowserSidebarTabListMetrics {
        capabilities.tabListMetrics
    }

    var body: some View {
        Group {
            if revealsOnHoverOnly {
                ZStack(alignment: .trailing) {
                    line
                    clearButton
                }
                .padding(.vertical, metrics.dividerVerticalInset)
            } else {
                line
                    .overlay(alignment: .trailing) { clearButton }
                    .padding(
                        .top,
                        hasSavedTabsEndBand ? max(0, touchSpacing - metrics.savedSectionEndBandHeight) : touchSpacing
                    )
                    .padding(.bottom, touchSpacing)
            }
        }
        .padding(.horizontal, metrics.dividerHorizontalInset)
    }

    private var line: some View {
        Divider()
            .frame(height: 1 / displayScale)
            .padding(.trailing, showsClearButton ? clearActionOcclusion : 0)
    }

    private var clearButton: some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                if revealsOnHoverOnly { Text("Clear") }
                Image(systemName: "archivebox")
                Image(systemName: "arrow.down")
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                clearLabelWidth = width
            }
            .frame(
                minWidth: revealsOnHoverOnly ? nil : Self.touchTarget,
                minHeight: revealsOnHoverOnly ? nil : Self.touchTarget
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
        .opacity(showsClearButton ? 1 : 0)
        .disabled(!canClear || !showsClearButton)
        .accessibilityHidden(!showsClearButton)
        .accessibilityLabel("Clear Open Tabs")
        .accessibilityHint("Moves all current tabs to Archive")
    }

    /// How much of the line's trailing end the clear control takes: its
    /// label, centered in its hit target, and the gap before it.
    private var clearActionOcclusion: CGFloat {
        let target = revealsOnHoverOnly ? clearLabelWidth : max(Self.touchTarget, clearLabelWidth)
        return (target + clearLabelWidth) / 2 + metrics.clearActionGap
    }

    private var touchSpacing: CGFloat {
        max(22, metrics.dividerVerticalInset)
    }

    private var showsClearButton: Bool {
        !revealsOnHoverOnly || (showsClearAction && canClear)
    }

    private var revealsOnHoverOnly: Bool {
        capabilities.revealsRowControlsOnHoverOnly
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCurrentTabsDivider(
            capabilities: BrowserInteractionCapabilities(), showsClearAction: true, canClear: true, clear: {}
        ).padding().frame(width: 320)
    }
#endif
