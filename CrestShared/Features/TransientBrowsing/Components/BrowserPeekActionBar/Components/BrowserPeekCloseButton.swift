import SwiftUI

/// Closes a Peek: an X on a disc of Liquid Glass, as tall as the controls
/// beside it.
struct BrowserPeekCloseButton: View {
    let accessibilityLabel: LocalizedStringKey
    let help: LocalizedStringKey
    var style = BrowserPeekControlStyle.actionBar
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
                .frame(width: style.height, height: style.height)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
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
