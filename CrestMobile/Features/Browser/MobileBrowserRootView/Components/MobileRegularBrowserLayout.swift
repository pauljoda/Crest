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
