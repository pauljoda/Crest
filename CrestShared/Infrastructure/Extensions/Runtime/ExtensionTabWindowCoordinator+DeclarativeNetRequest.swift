import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    /// The wire shape of both rulesets.
    static func emulatedHeaderRulesetsPayload(
        _ rulesets: BrowserExtensionEmulatedHeaderRulesets
    ) -> [String: Any] {
        [
            BrowserExtensionEmulatedHeaderRuleset.session.rawValue: rulesets.session.map(\.payload),
            BrowserExtensionEmulatedHeaderRuleset.dynamic.rawValue: rulesets.dynamic.map(\.payload),
        ]
    }

    func declarativeNetRequestEventMessage(
        _ rulesets: BrowserExtensionEmulatedHeaderRulesets
    ) -> [String: Any] {
        ["api": "dnr.event", "rulesets": Self.emulatedHeaderRulesetsPayload(rulesets)]
    }

    func handleCapabilityBrokerDeclarativeNetRequest(
        _ message: Any, applicationIdentifier: String?, controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard applicationIdentifier == BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
            let payload = message as? [String: Any], let api = payload["api"] as? String,
            BrowserExtensionDeclarativeNetRequestBrokerRequest.Operation(rawValue: api) != nil
        else { return false }
        do {
            let request = try BrowserExtensionDeclarativeNetRequestBrokerRequest(message: payload)
            guard let authorization = verifiedNativeMessagingAuthorizations[ObjectIdentifier(extensionContext)]
            else {
                throw BrowserExtensionNativeMessagingError.unverifiedExtension
            }
            guard authorization.allowsInternalCapabilityBroker,
                BrowserExtensionDeclarativeNetRequestBrokerRequest.requiredCapabilities.contains(
                    where: authorization.grants)
            else {
                throw BrowserExtensionCapabilityBrokerError.permissionDenied("declarativeNetRequest")
            }
            guard let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: extensionContext),
                let service = declarativeNetRequestService, let client = authorization.clientID
            else {
                throw BrowserExtensionEmulatedHeaderRuleError.unavailable
            }
            service.register(client: client, spaceID: spaceID)
            switch request.operation {
            case .setRules:
                guard let ruleset = request.ruleset else {
                    throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest
                }
                service.setRules(request.rules, ruleset: ruleset, for: client, in: spaceID)
                replyHandler(["ok": true], nil)
            case .rules:
                replyHandler(
                    [
                        "rulesets": Self.emulatedHeaderRulesetsPayload(
                            service.rulesets(for: client, in: spaceID))
                    ], nil)
            }
        } catch {
            replyHandler(nil, error)
        }
        return true
    }
}
