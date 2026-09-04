import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    /// Runs `chrome.identity.launchWebAuthFlow` for one extension.
    ///
    /// Nothing about the redirect comes from JavaScript. The origin Crest
    /// watches for is derived from the loaded context's own base URL, which is
    /// the same string WebKit serves the package's pages from, so an extension
    /// cannot ask to be handed a URL — and the authorization code in it — from
    /// an origin it does not own.
    ///
    /// Chrome queues a second flow behind the first. Crest refuses it instead,
    /// with the load failure Chrome uses for a flow that could not start: a
    /// queued invisible web view is a resource an extension can grow without
    /// bound, and every package Crest has seen retries rather than waits.
    func handleCapabilityBrokerIdentity(
        _ message: Any, applicationIdentifier: String?, controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard applicationIdentifier == BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
            let payload = message as? [String: Any],
            (payload["api"] as? String) == BrowserExtensionIdentityBrokerRequest.api
        else { return false }
        do {
            let request = try BrowserExtensionIdentityBrokerRequest(message: payload)
            guard let authorization = verifiedNativeMessagingAuthorizations[ObjectIdentifier(extensionContext)]
            else {
                throw BrowserExtensionNativeMessagingError.unverifiedExtension
            }
            guard authorization.allowsInternalCapabilityBroker, authorization.grants("identity") else {
                throw BrowserExtensionCapabilityBrokerError.permissionDenied("identity")
            }
            guard let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: extensionContext),
                let runtimeID = extensionContext.baseURL.host,
                let redirectOrigin = BrowserExtensionIdentityRedirectOrigin.origin(runtimeID: runtimeID),
                let host = webAuthFlowHost
            else {
                throw BrowserExtensionIdentityBrokerError.pageLoadFailure
            }
            let key = ObjectIdentifier(extensionContext)
            guard !webAuthFlowsInFlight.contains(key) else {
                throw BrowserExtensionIdentityBrokerError.pageLoadFailure
            }
            webAuthFlowsInFlight.insert(key)
            let hosted = BrowserExtensionWebAuthFlowRequest(
                url: request.url,
                redirectOrigin: redirectOrigin,
                isInteractive: request.isInteractive,
                abortsOnLoadForNonInteractive: request.abortsOnLoadForNonInteractive,
                nonInteractiveTimeout: request.nonInteractiveTimeout,
                spaceID: spaceID,
                extensionID: runtimeID,
                extensionDisplayName: extensionContext.webExtension.displayName ?? "Extension"
            )
            Task { @MainActor [weak self] in
                defer { self?.webAuthFlowsInFlight.remove(key) }
                do {
                    // The only place this URL is allowed to go. It is not
                    // logged, traced, or stored: its query carries the code.
                    let redirect = try await host.runWebAuthFlow(hosted)
                    replyHandler(["url": redirect.absoluteString], nil)
                } catch {
                    replyHandler(nil, Self.identityBrokerError(error))
                }
            }
        } catch {
            replyHandler(nil, error)
        }
        return true
    }

    /// Restates a host failure in Chrome's own words.
    ///
    /// A host that fails for a reason Crest has no Chrome text for reports the
    /// load failure rather than leaking its own description into an extension.
    private static func identityBrokerError(_ error: any Error) -> any Error {
        (error as? BrowserExtensionIdentityBrokerError)
            ?? BrowserExtensionIdentityBrokerError.pageLoadFailure
    }
}
