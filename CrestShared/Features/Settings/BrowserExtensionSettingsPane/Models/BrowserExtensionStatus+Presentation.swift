import SwiftUI

extension BrowserExtensionStatus {
    var title: LocalizedStringKey {
        switch self {
        case .on: "On"
        case .off: "Off"
        case .needsAttention: "Needs attention"
        }
    }

    var color: Color {
        switch self {
        case .on: .green
        case .off: .secondary
        case .needsAttention: .orange
        }
    }
}
