import SwiftUI

extension View {
    /// Touch has no window transparency, so a settings preview keeps the
    /// Space's atmosphere opaque.
    func browserPlatformSettingsAtmosphere() -> some View { self }
}
