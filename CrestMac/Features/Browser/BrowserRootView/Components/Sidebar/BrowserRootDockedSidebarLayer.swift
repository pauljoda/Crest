import SwiftUI

struct BrowserRootDockedSidebarLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let reduceMotion: Bool
    let content: Content

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        reduceMotion: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if presentation == .docked {
            content
                .frame(width: width)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .leading).combined(with: .opacity)
                )
        }
    }
}

#Preview("Browser Root Docked Sidebar") {
    BrowserRootDockedSidebarLayer(
        presentation: .docked,
        width: BrowserChromeLayout.sidebarIdealWidth,
        reduceMotion: false
    ) {
        Text("Sidebar")
    }
    .frame(height: 500)
}
