import SwiftUI

/// Opens a Peek's link menu: an ellipsis on a disc of Liquid Glass, as tall as
/// the controls beside it.
struct BrowserPeekMoreButton: View {
    var style = BrowserPeekControlStyle.actionBar
    let show: () -> Void

    var body: some View {
        Button(action: show) {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .fontWeight(.semibold)
                .frame(width: style.height, height: style.height)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityIdentifier("peek-link-menu-control")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserPeekMoreButton(show: {}).padding()
    }
#endif
