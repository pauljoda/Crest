import SwiftUI

extension View {
    /// Applies the field surface to a field-like row, such as a glyph beside a
    /// plain field, whose field's focus the caller tracks. The row is at least
    /// `minHeight` tall.
    func crestFieldSurface(isFocused: Bool, minHeight: CGFloat = CrestFieldMetrics.height) -> some View {
        modifier(CrestFieldSurface(isFocused: isFocused, minHeight: minHeight))
    }

    /// Tells the fields under this view which surface they sit on.
    func crestFieldSurfaceRole(_ role: CrestFieldSurfaceRole) -> some View {
        environment(\.crestFieldSurfaceRole, role)
    }
}
