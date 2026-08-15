import SwiftUI

struct BrowserPlatformHorizontalScrollerSuppressor: View {
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Horizontal Scroller Suppressor") {
    ZStack {
        RoundedRectangle(cornerRadius: CrestRadius.card)
            .fill(.blue.gradient)
        Text("Pager content")
            .foregroundStyle(.white)
        BrowserPlatformHorizontalScrollerSuppressor()
    }
    .frame(width: 320, height: 120)
    .padding()
}
