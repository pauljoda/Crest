import SwiftUI

struct MobileRegularBrowserLayout<SideBySide: View, Overlay: View>: View,
    BrowserChromeAnimating
{
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let layout: MobileRegularWindowLayout
    let sidebarIsPresented: Bool
    let isCommandPalettePresented: Bool
    let sideBySide: (CGFloat) -> SideBySide
    let overlay: (CGFloat) -> Overlay

    var body: some View {
        Group {
            switch layout {
            case .sideBySide(let sidebarWidth):
                sideBySide(sidebarWidth)
            case .overlay(let sidebarWidth):
                overlay(sidebarWidth)
            }
        }
        .animation(
            chromeAnimation(CrestMotion.chrome),
            value: sidebarIsPresented
        )
        .animation(
            chromeAnimation(CrestMotion.pane),
            value: isCommandPalettePresented
        )
    }
}

#Preview("Mobile Regular Browser Layout") {
    MobileRegularBrowserLayout(
        layout: .sideBySide(sidebarWidth: 320),
        sidebarIsPresented: true,
        isCommandPalettePresented: false,
        sideBySide: { _ in Color.indigo.opacity(0.2) },
        overlay: { _ in Color.orange.opacity(0.2) }
    )
}
