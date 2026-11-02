import SwiftUI

struct BrowserPeekCloseButton: View {
    let accessibilityLabel: LocalizedStringKey
    let help: LocalizedStringKey
    var style = BrowserPeekControlStyle.actionBar
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Label("Close", systemImage: "xmark")
                .frame(maxWidth: .infinity)
                .frame(height: style.height)
                .contentShape(style.shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: style.shape)
        .keyboardShortcut("w", modifiers: .command)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier("peek-close-control")
        .help(Text(help))
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserPeekCloseButton(accessibilityLabel: "Close Peek", help: "Close Peek", dismiss: {}).padding()
    }
#endif
