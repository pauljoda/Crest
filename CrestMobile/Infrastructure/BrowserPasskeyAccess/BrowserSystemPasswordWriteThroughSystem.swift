import AuthenticationServices
import Foundation

@MainActor
enum BrowserSystemPasswordWriteThroughSystem {
    private static let buildManifestKey =
        "CrestSystemPasswordWriteThroughManagedCapability"

    static var launchAvailability: BrowserSystemPasswordWriteThroughAvailability {
        availability(for: .current)
    }

    static func availability(
        for launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserSystemPasswordWriteThroughAvailability {
        BrowserSystemPasswordWriteThroughPolicy.availability(
            isMobilePlatform: true,
            supportsSystemAPI: supportsSystemAPI,
            hasManagedBrowserCapability: hasManagedBrowserCapability,
            isLaunchIsolated:
                BrowserLaunchIsolationPolicy.requiresIsolation(
                    launchEnvironment
                )
        )
    }

    static func offer(
        candidate: BrowserCredentialSaveCandidate,
        title: String,
        anchor: ASPresentationAnchor?,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) async throws {
        guard availability(for: launchEnvironment) == .available else {
            throw BrowserSystemPasswordWriteThroughError.unavailable
        }
        guard let anchor else {
            throw BrowserSystemPasswordWriteThroughError.missingPresentationAnchor
        }
        guard #available(iOS 26.2, *),
            let url = URL(string: candidate.origin.description),
            let scope = ASAutoFillURLScope(url: url)
        else {
            throw BrowserSystemPasswordWriteThroughError.invalidScope
        }

        try await ASCredentialDataManager().save(
            password: ASPasswordCredential(
                user: candidate.username,
                password: candidate.password
            ),
            for: scope,
            title: title,
            anchor: anchor
        )
    }

    private static var supportsSystemAPI: Bool {
        if #available(iOS 26.2, *) {
            true
        } else {
            false
        }
    }

    private static var hasManagedBrowserCapability: Bool {
        Bundle.main.object(forInfoDictionaryKey: buildManifestKey) as? Bool == true
    }
}
