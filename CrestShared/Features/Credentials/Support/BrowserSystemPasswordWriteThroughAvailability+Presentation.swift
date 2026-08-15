import Foundation

extension BrowserSystemPasswordWriteThroughAvailability {
    var detail: LocalizedStringResource {
        switch self {
        case .available:
            "After Crest saves in this Space, the system can ask whether to save or update a copy in your preferred password manager."
        case .unsupportedPlatform:
            "On Mac, WebKit and the system manage Passwords integration directly."
        case .isolatedLaunch:
            "System Passwords is unavailable while Crest is running an isolated session."
        case .systemVersionRequired:
            "Offering a copy to Passwords requires iOS or iPadOS 26.2 or later."
        case .managedBrowserCapabilityRequired:
            "This option becomes available after Apple approves Crest’s managed browser capability."
        }
    }
}
