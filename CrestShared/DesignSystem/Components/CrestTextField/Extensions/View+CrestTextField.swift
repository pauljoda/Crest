import SwiftUI

extension View {
    /// Adds Crest chrome while preserving the native field, keyboard, cursor,
    /// selection, autofill, submit behavior, and accessibility role.
    func crestTextField() -> some View {
        textFieldStyle(.plain)
            .crestFieldSurface()
    }

    /// Applies the field surface to a `SecureField` or a field-like row.
    func crestFieldSurface() -> some View {
        modifier(CrestFieldSurface())
    }
}

#Preview("Crest Text Field") {
    @Previewable @State var address = "example.com"

    TextField("Address", text: $address)
        .crestTextField()
        .padding()
        .frame(width: 360)
}
