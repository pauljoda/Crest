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
