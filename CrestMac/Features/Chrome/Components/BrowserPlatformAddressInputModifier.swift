import SwiftUI

struct BrowserPlatformAddressInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

#Preview("Address input") {
    TextField("Search or enter address", text: .constant("crestbrowser.com"))
        .modifier(BrowserPlatformAddressInputModifier())
        .frame(width: 360)
        .padding()
}
