import AppKit
import AuthenticationServices
import Foundation

/// macOS adapter that runs an emulated `identity.launchWebAuthFlow` through
/// `ASWebAuthenticationSession`.
///
/// The callback is translated at the last possible moment: a custom scheme maps
/// to `.customScheme(_:)`, and a web URL maps to `.https(host:path:)`. Whether
/// the latter is *allowed* is decided upstream by
/// ``BrowserExtensionWebAuthenticationService``, which knows which hosts Crest
/// is actually associated with — starting an unassociated `https` session would
/// simply never call back.
@MainActor
final class BrowserExtensionWebAuthenticationSystemSession:
    BrowserExtensionWebAuthenticationSessionStarting
{
    private let anchorProvider = BrowserExtensionWebAuthenticationAnchorProvider()
    private let resolveAnchor: @MainActor () -> NSWindow?
    private var activeSession: ASWebAuthenticationSession?

    /// - Parameter resolveAnchor: The window to present from. Defaults to the
    ///   app-level key-then-main lookup Crest's other presenters use.
    init(
        resolveAnchor: @escaping @MainActor () -> NSWindow? = {
            NSApp.keyWindow ?? NSApp.mainWindow
        }
    ) {
        self.resolveAnchor = resolveAnchor
    }

    func start(
        authorizationURL: URL,
        callback: BrowserExtensionWebAuthenticationCallback,
        prefersEphemeralSession: Bool
    ) async throws -> URL {
        guard let anchor = resolveAnchor() else {
            throw BrowserExtensionWebAuthenticationError.presentationFailure
        }
        guard let systemCallback = Self.systemCallback(for: callback) else {
            throw BrowserExtensionWebAuthenticationError.unsupportedCallback
        }
        anchorProvider.setAnchor(anchor)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callback: systemCallback
            ) { redirectURL, error in
                if let error {
                    continuation.resume(throwing: Self.mapped(error))
                    return
                }
                guard let redirectURL else {
                    continuation.resume(
                        throwing: BrowserExtensionWebAuthenticationError
                            .invalidCallback
                    )
                    return
                }
                continuation.resume(returning: redirectURL)
            }
            session.presentationContextProvider = anchorProvider
            session.prefersEphemeralWebBrowserSession = prefersEphemeralSession
            activeSession = session

            guard session.start() else {
                activeSession = nil
                continuation.resume(
                    throwing: BrowserExtensionWebAuthenticationError
                        .presentationFailure
                )
                return
            }
        }
    }

    private static func systemCallback(
        for callback: BrowserExtensionWebAuthenticationCallback
    ) -> ASWebAuthenticationSession.Callback? {
        guard let scheme = callback.scheme, !scheme.isEmpty else { return nil }
        guard callback.usesWebScheme else {
            return .customScheme(scheme)
        }
        guard scheme == "https", let host = callback.host else { return nil }
        return .https(host: host, path: callback.path)
    }

    private static func mapped(
        _ error: any Error
    ) -> BrowserExtensionWebAuthenticationError {
        guard let sessionError = error as? ASWebAuthenticationSessionError else {
            return .presentationFailure
        }
        switch sessionError.code {
        case .canceledLogin:
            return .userCanceled
        case .presentationContextNotProvided, .presentationContextInvalid:
            return .presentationFailure
        default:
            return .presentationFailure
        }
    }
}
