import SwiftUI

struct BrowserUnloadedPageSurface: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

#Preview("Unloaded Browser Page") {
    BrowserUnloadedPageSurface()
        .frame(width: 640, height: 420)
}
