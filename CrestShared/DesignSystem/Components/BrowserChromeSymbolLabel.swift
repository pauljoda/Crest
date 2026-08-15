import SwiftUI

/// One SF Symbol geometry for adjacent browser chrome buttons. The shared
/// button style owns the hit frame, keeping every symbol centered without
/// platform-view offsets or custom baselines.
struct BrowserChromeSymbolLabel: View {
    let systemName: String
    var pointSize = BrowserReloadFeedbackPolicy.symbolPointSize

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: .regular))
    }
}

#Preview("Chrome Symbol") {
    BrowserChromeSymbolLabel(systemName: "arrow.clockwise")
        .padding()
}
