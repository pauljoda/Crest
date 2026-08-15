import SwiftUI

/// Keeps the window backing clear without changing the opacity of its controls or web content.
struct BrowserWindowTransparencyBridge: NSViewRepresentable {
    let isEnabled: Bool
    @Binding var isWindowFocused: Bool

    func makeNSView(context: Context) -> BrowserWindowTransparencyHostView {
        let view = BrowserWindowTransparencyHostView(
            isTransparencyEnabled: isEnabled
        )
        view.focusChanged = { isWindowFocused = $0 }
        return view
    }

    func updateNSView(
        _ nsView: BrowserWindowTransparencyHostView,
        context: Context
    ) {
        nsView.focusChanged = { isWindowFocused = $0 }
        nsView.isTransparencyEnabled = isEnabled
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowTransparencyHostView,
        coordinator: ()
    ) {
        nsView.restoreWindowBacking()
    }
}

#Preview("Opaque window bridge") {
    @Previewable @State var isWindowFocused = true
    Color.clear
        .frame(width: 240, height: 120)
        .overlay {
            BrowserWindowTransparencyBridge(
                isEnabled: false,
                isWindowFocused: $isWindowFocused
            )
            .frame(width: 0, height: 0)
        }
}
