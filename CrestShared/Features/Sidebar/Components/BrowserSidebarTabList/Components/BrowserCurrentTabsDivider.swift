import SwiftUI

/// The seam between the saved run and the current one, on every shell.
///
/// Pointer-only shells reveal Clear on hover. Touch and non-hover shells keep
/// an icon mounted so clearing never requires a pointer. The divider reserves
/// room for the control whenever it is visible.
struct BrowserCurrentTabsDivider: View {
    let capabilities: BrowserInteractionCapabilities
    /// Whether the shell is currently in the state that reveals the control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    /// Whether there is anything left to clear.
    let canClear: Bool
    let clear: () -> Void

    private var metrics: BrowserSidebarTabListMetrics {
        BrowserSidebarInteractionPolicy.tabListMetrics(capabilities)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Divider()
                .padding(
                    .trailing,
                    showsClearButton ? metrics.clearActionOcclusionWidth : 0
                )

            Button(action: clear) {
                if revealsOnHoverOnly {
                    Label("Clear", systemImage: "arrow.down")
                        .labelStyle(.titleAndIcon)
                } else {
                    Label("Clear Open Tabs", systemImage: "arrow.down")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .opacity(showsClearButton ? 1 : 0)
            .disabled(!canClear || !showsClearButton)
            .accessibilityHidden(!showsClearButton)
            .accessibilityHint("Moves all current tabs to Archive")
        }
        .padding(.horizontal, metrics.dividerHorizontalInset)
        .padding(.vertical, metrics.dividerVerticalInset)
    }

    private var showsClearButton: Bool {
        !revealsOnHoverOnly || (showsClearAction && canClear)
    }

    private var revealsOnHoverOnly: Bool {
        BrowserSidebarInteractionPolicy.revealsRowControlsOnHoverOnly(capabilities)
    }
}
