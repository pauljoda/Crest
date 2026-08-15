import Foundation

enum BrowserSoftwareUpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable
    case nightly
    case development

    var id: Self { self }

    var title: String {
        switch self {
        case .stable: "Stable"
        case .nightly: "Nightly"
        case .development: "Development"
        }
    }

    var guidance: String {
        switch self {
        case .stable:
            "Recommended releases intended for everyday use."
        case .nightly:
            "Daily snapshots of current development. Nightly builds may be less reliable."
        case .development:
            "The latest signed build from public main. Development builds can change several times a day."
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .nightly: ["nightly"]
        case .development: ["development"]
        }
    }

    var customFeedURL: URL? {
        switch self {
        case .stable, .nightly:
            nil
        case .development:
            URL(
                string: "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-development.xml"
            )
        }
    }
}
