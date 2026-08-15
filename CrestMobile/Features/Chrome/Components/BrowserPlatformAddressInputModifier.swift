import SwiftUI

struct BrowserPlatformAddressInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(BrowserAddressKeyboardPolicy.keyboardType)
            .submitLabel(.go)
    }
}

#Preview("Address input") {
    TextField("Search or enter address", text: .constant("crestbrowser.com"))
        .modifier(BrowserPlatformAddressInputModifier())
        .padding()
}
