import Foundation

struct BrowserAboutBuildInformation: Equatable, Sendable {
    let version: String
    let build: String
    let bundleIdentifier: String

    static let current = BrowserAboutBuildInformation(bundle: .main)

    init(bundle: Bundle) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleIdentifier: bundle.bundleIdentifier
        )
    }

    init(
        infoDictionary: [String: Any],
        bundleIdentifier: String?
    ) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        build = infoDictionary["CFBundleVersion"] as? String ?? "—"
        self.bundleIdentifier =
            bundleIdentifier ?? ProductIdentity.bundleIdentifier
    }
}

enum BrowserAboutLinks {
    static var feedback: URL {
        url("https://www.reddit.com/r/CrestBrowser")
    }

    static var issues: URL {
        url("https://github.com/crest-browser/Crest/issues/new/choose")
    }

    static var roadmap: URL {
        url("https://github.com/users/pauljoda/projects/3")
    }

    private static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid About link: \(value)")
        }
        return url
    }
}
