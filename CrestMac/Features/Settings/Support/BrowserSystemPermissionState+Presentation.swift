import SwiftUI

extension BrowserSystemPermissionState {
    var title: LocalizedStringResource {
        switch self {
        case .checking: "Checking…"
        case .notRequested: "Not requested"
        case .allowed: "Allowed"
        case .blocked: "Needs attention"
        case .restricted: "Restricted by macOS"
        case .unavailable: "Unavailable"
        case .notChecked: "Not checked"
        case .chooseEachTime: "Ask where to save"
        }
    }

    var symbol: String {
        switch self {
        case .allowed: "checkmark.circle.fill"
        case .blocked, .restricted: "exclamationmark.circle.fill"
        default: "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .allowed: .green
        case .blocked, .restricted: .orange
        default: .secondary
        }
    }
}
