import SwiftUI

/// A selection laid on Crest's light paper rather than the device's
/// material: how much of what lies under the sheet shows through it, and
/// what lies directly under it.
struct CrestPaperSheet: Equatable {
    // MARK: - Static Variables

    /// Solid paper, which nothing under it shows through.
    static let opaque = CrestPaperSheet()

    // MARK: - Variables

    /// How opaque the sheet is, from clear to solid.
    var opacity: Double = 1
    /// A color laid under the sheet, as a selected pin's site color is, or nil
    /// for whatever the surface shows when it is not selected.
    var ground: Color? = nil

    /// Whether what the surface shows at rest shows through the sheet: it
    /// lets some light through and brings no ground of its own.
    var showsRestingSurface: Bool { ground == nil && opacity < 1 }
}
