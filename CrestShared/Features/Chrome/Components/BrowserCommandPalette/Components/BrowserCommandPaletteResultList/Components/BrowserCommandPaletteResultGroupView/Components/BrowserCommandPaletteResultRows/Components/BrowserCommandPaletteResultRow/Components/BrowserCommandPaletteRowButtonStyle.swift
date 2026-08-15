import SwiftUI

struct BrowserCommandPaletteRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, BrowserCommandPaletteMetrics.rowHorizontalPadding)
            .frame(minHeight: BrowserCommandPaletteMetrics.resultRowHeight)
            .contentShape(.rect)
            .background(
                isSelected
                    ? Color.accentColor.opacity(
                        BrowserCommandPaletteMetrics.selectedRowOpacity
                    )
                    : Color.primary.opacity(
                        BrowserCommandPaletteMetrics.restingRowOpacity
                    ),
                in: .rect(cornerRadius: BrowserCommandPaletteMetrics.rowCornerRadius)
            )
    }
}

#Preview("Command Palette Row Styles") {
    VStack(spacing: CrestSpacing.small) {
        Button("Selected Result", systemImage: "safari", action: {})
            .buttonStyle(
                BrowserCommandPaletteRowButtonStyle(isSelected: true)
            )

        Button("Resting Result", systemImage: "clock", action: {})
            .buttonStyle(
                BrowserCommandPaletteRowButtonStyle(isSelected: false)
            )
    }
    .frame(width: BrowserCommandPaletteMetrics.maximumCardWidth)
    .padding(CrestSpacing.large)
}
