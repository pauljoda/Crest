import Foundation

enum BrowserSoftwareUpdateChannel: String, Identifiable, Sendable, CaseIterable {
    case stable
    case nightly
    case development
    case experimental

    /// Experimental is offered only by a build packaged for it, so once the
    /// branch it serves reaches Development, normal builds do not show an
    /// obsolete choice.
    static var allCases: [Self] {
        var channels: [Self] = [.stable, .nightly, .development]

        let bundledDefault = Bundle.main.object(
            forInfoDictionaryKey: "CrestDefaultUpdateChannel"
        ) as? String

        if bundledDefault == Self.experimental.rawValue {
            channels.append(.experimental)
        }

        return channels
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .stable: "Stable"
        case .nightly: "Nightly"
        case .development: "Development"
        case .experimental: "Experimental"
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
        case .experimental:
            "Experimental branch builds for testing work before it reaches Development."
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .nightly: ["nightly"]
        case .development: ["development"]
        case .experimental: ["experimental"]
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
        case .experimental:
            // Experimental publishes the Chromium build as its default and a
            // WebKit build as an alternate download. Each follows its own feed,
            // so an update never changes the engine someone chose.
            URL(
                string: BrowserEngineRegistration.current.implementationId.hasPrefix("crest.webkit")
                    ? "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-experimental-webkit.xml"
                    : "https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-experimental.xml"
            )
        }
    }
}
