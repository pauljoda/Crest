enum BrowserExtensionDiscoverySource: Equatable, Sendable {
    case safariApplication(name: String)

    var title: String {
        switch self {
        case .safariApplication:
            "Safari App"
        }
    }

    var detail: String {
        switch self {
        case .safariApplication(let name):
            name
        }
    }

    var symbol: String {
        switch self {
        case .safariApplication:
            "safari"
        }
    }
}

struct BrowserExtensionDiscoveryItem: Equatable, Identifiable {
    let candidate: BrowserSafariWebExtensionCandidate
    let source: BrowserExtensionDiscoverySource

    var id: String { candidate.id }

    init(candidate: BrowserSafariWebExtensionCandidate) {
        self.candidate = candidate
        source = .safariApplication(
            name: candidate.applicationDisplayName
        )
    }
}
