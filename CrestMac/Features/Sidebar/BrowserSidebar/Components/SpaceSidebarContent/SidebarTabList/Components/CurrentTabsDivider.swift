import SwiftUI

struct CurrentTabsDivider: View {
    let showsClearAction: Bool
    let canClear: Bool
    let clear: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Divider()
                .padding(
                    .trailing,
                    showsClearButton
                        ? BrowserSidebarMetrics.clearActionOcclusionWidth
                        : 0
                )

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
        .padding(
            .horizontal,
            BrowserSidebarMetrics.tabListDividerHorizontalInset
        )
        .padding(
            .vertical,
            BrowserSidebarMetrics.tabListDividerVerticalInset
        )
    }

    private var showsClearButton: Bool {
        showsClearAction && canClear
    }
}
