import SwiftUI

struct BrowserPlatformHorizontalScrollerSuppressor: View {
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
