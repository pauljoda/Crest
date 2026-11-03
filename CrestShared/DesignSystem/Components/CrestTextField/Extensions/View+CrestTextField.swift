import SwiftUI

extension View {
    /// Adds Crest chrome to a `TextField` or `SecureField` while preserving the
    /// native field, keyboard, cursor, selection, autofill, submit behavior,
    /// and accessibility role.
    func crestTextField() -> some View {
        textFieldStyle(.plain)
            .modifier(CrestFieldSurface())
    }

    /// Applies the field surface to a field-like row, such as a glyph beside a
    /// plain field, whose field's focus the caller tracks.
    func crestFieldSurface(isFocused: Bool) -> some View {
        modifier(CrestFieldSurface(rowFocus: isFocused))
    }
}
