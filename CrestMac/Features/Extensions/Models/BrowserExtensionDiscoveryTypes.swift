enum BrowserExtensionDiscoverySource: Equatable, Sendable {
    case safariApplication(name: String)
    case safariCustom

    var title: String {
        switch self {
        case .safariApplication:
            "Safari App"
        case .safariCustom:
            "Safari Custom Extension"
        }
    }

    var detail: String {
        switch self {
        case .safariApplication(let name):
            name
        case .safariCustom:
            "Created in Safari"
        }
    }

    var symbol: String {
        switch self {
        case .safariApplication:
            "safari"
        case .safariCustom:
            "wand.and.sparkles"
        }
    }
}

enum BrowserExtensionDiscoveryCandidate: Equatable, Identifiable {
    case safariApplication(BrowserSafariWebExtensionCandidate)
    case safariCustom(BrowserLocalExtensionCandidate)

    var id: String {
        switch self {
        case .safariApplication(let candidate): candidate.id
        case .safariCustom(let candidate): candidate.id
        }
    }

    var displayName: String {
        switch self {
        case .safariApplication(let candidate): candidate.displayName
        case .safariCustom(let candidate): candidate.displayName
        }
    }

    var version: String? {
        switch self {
        case .safariApplication(let candidate): candidate.version
        case .safariCustom(let candidate): candidate.version
        }
    }

    var displayDescription: String? {
        switch self {
        case .safariApplication(let candidate): candidate.displayDescription
        case .safariCustom(let candidate): candidate.displayDescription
        }
    }

    var requestedPermissions: [String] {
        switch self {
        case .safariApplication(let candidate):
            candidate.requestedPermissions
        case .safariCustom(let candidate):
            candidate.requestedPermissions
        }
    }

    var requestedHosts: [String] {
        switch self {
        case .safariApplication(let candidate): candidate.requestedHosts
        case .safariCustom(let candidate): candidate.requestedHosts
        }
    }

    var errors: [String] {
        switch self {
        case .safariApplication(let candidate): candidate.errors
        case .safariCustom(let candidate): candidate.errors
        }
    }

    var iconPayload: BrowserExtensionIconPayload? {
        switch self {
        case .safariApplication(let candidate): candidate.iconPayload
        case .safariCustom(let candidate): candidate.iconPayload
        }
    }
}

struct BrowserExtensionDiscoveryItem: Equatable, Identifiable {
    let candidate: BrowserExtensionDiscoveryCandidate
    let source: BrowserExtensionDiscoverySource

    var id: String { candidate.id }

    init(candidate: BrowserSafariWebExtensionCandidate) {
        self.candidate = .safariApplication(candidate)
        source = .safariApplication(
            name: candidate.applicationDisplayName
        )
    }

    init(candidate: BrowserLocalExtensionCandidate) {
        self.candidate = .safariCustom(candidate)
        source = .safariCustom
    }
}
