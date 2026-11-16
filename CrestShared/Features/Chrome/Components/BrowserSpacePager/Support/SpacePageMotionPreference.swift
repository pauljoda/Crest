import Foundation

/// App-wide motion preference, independent of Space branding and sidebar
/// motion: whether pages slide when a window switches Spaces, on every
/// platform. Where they don't, or Reduce Motion is on, they fade.
enum SpacePageMotionPreference {
    static let key = "crest.appearance.animate-space-pages"
    static let defaultValue = true

    /// Whether pages slide, where the person `animatesPages` and the system
    /// may `reduceMotion`.
    static func slides(animatesPages: Bool, reduceMotion: Bool) -> Bool {
        animatesPages && !reduceMotion
    }
}
