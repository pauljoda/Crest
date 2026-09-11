import SwiftUI

extension EnvironmentValues {
    /// How opaque a Space's atmosphere is inside a settings preview.
    ///
    /// The desktop lowers it to match focused-window transparency so the
    /// miniature answers that control too; touch has no such choice and leaves
    /// the atmosphere opaque.
    @Entry var browserSettingsAtmosphereOpacity: Double = 1
}
