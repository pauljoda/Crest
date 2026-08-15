import SwiftUI

struct NewTabRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New Tab", systemImage: "plus")
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(height: CrestLayout.sidebarRowHeight)
        .crestHoverSurface(
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
        .padding(.horizontal, CrestSpacing.small)
        .help("New Tab (⌘T)")
    }
}

#Preview("New Tab hover row") {
    NewTabRow(action: {})
        .frame(width: 280)
        .padding(.vertical, CrestSpacing.small)
}
