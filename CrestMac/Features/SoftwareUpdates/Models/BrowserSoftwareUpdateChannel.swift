import Foundation

enum BrowserSoftwareUpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable
    case nightly

    var id: Self { self }

    var title: String {
        switch self {
        case .stable: "Stable"
        case .nightly: "Nightly"
        }
    }

    var guidance: String {
        switch self {
        case .stable:
            "Recommended releases intended for everyday use."
        case .nightly:
            "Early builds from current development. Nightly builds may be less reliable."
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .nightly: ["nightly"]
        }
    }
}
