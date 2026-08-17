import SwiftUI

struct BrowserPeekDestinationPrimaryButton: View {
    let selectedSpace: BrowserSpace?
    let openInSelectedSpace: () -> Void

    var body: some View {
        Button(action: openInSelectedSpace) {
            HStack(spacing: BrowserPeekChromePolicy.destinationContentSpacing) {
                if let selectedSpace {
                    BrowserSpaceIdentityIcon(
                        space: selectedSpace,
                        size: BrowserPeekChromePolicy.destinationIconSize
                    )
                } else {
                    Image(systemName: "square.grid.2x2")
                }
                Text(BrowserPeekChromePolicy.openInTitle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, BrowserPeekChromePolicy.destinationLeadingInset)
            .frame(height: BrowserPeekChromePolicy.controlHeight)
            .contentShape(.rect)
        }
        .keyboardShortcut("o", modifiers: .command)
        .accessibilityLabel(Text(BrowserPeekChromePolicy.openInTitle))
        .accessibilityValue(Text(selectedSpace?.name ?? "Space"))
        .accessibilityIdentifier("peek-open-selected-space")
        .help("Open in \(selectedSpace?.name ?? "Space") (⌘O)")
    }
}
