import SwiftUI

extension SystemTint {
    /// The platform color for the core's tint. This is the one place a tint
    /// becomes a color.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .purple: .purple
        case .blue: .blue
        }
    }
}
