import Foundation

enum BrowserPasskeyAccessStatus: Equatable, Sendable {
    case checking
    case managedCapabilityRequired
    case deviceNotConfigured
    case notDetermined
    case authorized
    case denied

    var title: String {
        switch self {
        case .checking:
            String(localized: "Checking passkey access")
        case .managedCapabilityRequired:
            String(localized: "Awaiting Apple approval")
        case .deviceNotConfigured:
            String(localized: "Passkeys aren’t configured")
        case .notDetermined:
            String(localized: "Permission required")
        case .authorized:
            String(localized: "Ready for websites")
        case .denied:
            String(localized: "Passkey access is off")
        }
    }

    var detail: String {
        switch self {
        case .checking:
            String(
                localized: "Crest is checking this build and the system’s browser-passkey setting."
            )
        case .managedCapabilityRequired:
            String(
                localized: "This build cannot request browser-wide passkey access until Apple approves Crest’s managed capability."
            )
        case .deviceNotConfigured:
            String(
                localized: "Configure passkeys in system settings, then reopen Crest."
            )
        case .notDetermined:
            String(
                localized: "Allow Crest to use the system’s passkey providers for the website in the active page."
            )
        case .authorized:
            String(
                localized: "WebKit can use the system’s passkey providers for the website in the active page."
            )
        case .denied:
            String(
                localized: "Turn on Crest under Privacy & Security > Passkeys Access for Web Browsers in system settings."
            )
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            "ellipsis.circle"
        case .managedCapabilityRequired:
            "checkmark.seal"
        case .deviceNotConfigured:
            "key.slash"
        case .notDetermined:
            "person.badge.key"
        case .authorized:
            "person.badge.key.fill"
        case .denied:
            "hand.raised.slash"
        }
    }
}
