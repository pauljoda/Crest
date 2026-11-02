import SwiftUI

/// The space around a palette grown out of an address bar, which a tap
/// closes the palette from.
struct BrowserPlatformCommandPaletteDismissLayer: View {
    let dismiss: () -> Void

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .onTapGesture(perform: dismiss)
    }
}
