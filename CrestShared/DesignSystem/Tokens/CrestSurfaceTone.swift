import SwiftUI

/// Whether the surfaces drawn in the device's material, and the text on
/// them, read light or dark: as their Space reads, always light, always
/// dark, or as the window does. The same four choices a Space's text offers.
///
/// One choice for the whole device, made in Look and Feel beside the
/// material it tones.
struct CrestSurfaceTone: Hashable, Sendable {
    // MARK: - Static Variables

    /// As the Space the surface stands on reads: dark over a dark Space,
    /// light over a light one.
    static let automatic = CrestSurfaceTone(name: "automatic", title: "Automatic")
    static let light = CrestSurfaceTone(name: "light", title: "Light")
    static let dark = CrestSurfaceTone(name: "dark", title: "Dark")
    /// As the window reads, the same on every Space.
    static let system = CrestSurfaceTone(name: "system", title: "System")
    static let all = [automatic, light, dark, system]
    static let standard = automatic

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource) {
        self.name = name
        self.title = title
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> CrestSurfaceTone? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Scheme

    /// The scheme a surface draws in over content in `scheme`, by the
    /// material color this device chose.
    @MainActor
    static func shownScheme(over scheme: ColorScheme, window: ColorScheme?) -> ColorScheme {
        BrowserDeviceAppearanceStore.shared.surfaceTone.colorScheme(over: scheme, window: window)
    }

    /// The scheme a surface draws in over content in `scheme`, in a window
    /// that reads in `window`, or in `scheme` itself when no window scheme
    /// is known.
    func colorScheme(over scheme: ColorScheme, window: ColorScheme?) -> ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: window ?? scheme
        default: scheme
        }
    }

    // MARK: - Actions - Identity

    static func == (lhs: CrestSurfaceTone, rhs: CrestSurfaceTone) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
