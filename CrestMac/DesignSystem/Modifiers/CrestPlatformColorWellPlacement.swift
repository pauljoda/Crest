import SwiftUI

/// The Mac hangs a color well's popover below the well, as the well starts
/// out asking, so growing for a gradient's controls extends it downward and
/// never moves what it shows.
struct CrestPlatformColorWellPlacement: ViewModifier {
    @Binding var arrowEdge: Edge?

    func body(content: Content) -> some View {
        content
    }
}
