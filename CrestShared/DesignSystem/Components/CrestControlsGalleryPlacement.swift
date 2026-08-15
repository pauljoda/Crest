#if DEBUG
    import SwiftUI

    /// Mirrors the controls gallery's placement choice: three values, one glyph each.
    enum CrestControlsGalleryPlacement: String, Hashable, CaseIterable {
        case pinned
        case saved
        case open

        var title: LocalizedStringKey {
            switch self {
            case .pinned: "Pinned"
            case .saved: "Saved"
            case .open: "Open"
            }
        }

        var symbol: String {
            switch self {
            case .pinned: "pin.fill"
            case .saved: "bookmark.fill"
            case .open: "rectangle.stack.fill"
            }
        }
    }
#endif
