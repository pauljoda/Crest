import SwiftUI

/// The seam between the saved run and the current one, on every shell.
///
/// Where a pointer can reveal it, the seam also carries the control that
/// archives every current tab at once: the divider gives up its trailing end
/// while the control is showing, so the two never overlap. A shell that cannot
/// reveal a control on hover draws the seam alone and leaves clearing to the
/// Space header's menu, which a finger can reach.
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

            if metrics.carriesClearAction {
                Button("Clear", systemImage: "arrow.down", action: clear)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .opacity(showsClearButton ? 1 : 0)
                    .disabled(!showsClearButton)
                    .accessibilityHidden(!showsClearButton)
                    .accessibilityHint("Moves all current tabs to Archive")
            }
        }
        .padding(.horizontal, metrics.dividerHorizontalInset)
        .padding(.vertical, metrics.dividerVerticalInset)
    }

    private var showsClearButton: Bool {
        metrics.carriesClearAction && showsClearAction && canClear
    }
}
