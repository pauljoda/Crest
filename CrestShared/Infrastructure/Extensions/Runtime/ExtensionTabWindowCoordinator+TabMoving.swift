import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    func handleCapabilityBrokerTabMove(
        _ message: Any, applicationIdentifier: String?, controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard applicationIdentifier == BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
            let payload = message as? [String: Any], payload["api"] as? String == "tabs.move"
        else { return false }
        do {
            guard
                verifiedNativeMessagingAuthorizations[ObjectIdentifier(extensionContext)]?
                    .allowsInternalCapabilityBroker == true,
                let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: extensionContext)
            else { throw BrowserExtensionNativeMessagingError.unverifiedExtension }
            guard let number = payload["index"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                number.doubleValue >= -1, number.doubleValue <= Double(Int32.max),
                let raw = payload["tabs"] as? [[String: Any]], !raw.isEmpty
            else { throw BrowserExtensionTabGroupBrokerError.invalidRequest }
            let window = try brokerWindow(in: spaceID, message: raw[0])
            let space = brokerState(in: spaceID, window: window)
            for target in raw {
                guard try brokerWindow(in: spaceID, message: target) === window else {
                    throw BrowserExtensionTabGroupBrokerError.invalidRequest
                }
            }
            let liveTabs = Set(space.tabs.map(\.id)).subtracting((transientTabsBySpace[spaceID] ?? []).map(\.id))
            let ids = try raw.map { try BrowserExtensionTabTarget(message: $0).resolve(in: space, liveTabs: liveTabs) }
            guard let first = ids.first, let browser = browser(for: first, in: spaceID) else {
                throw BrowserExtensionTabGroupBrokerError.invalidRequest
            }
            guard
                browser.moveExtensionTabs(
                    ids, in: spaceID, to: number.intValue, among: hostWindows.isEmpty ? nil : liveTabs)
            else {
                throw BrowserExtensionCapabilityBrokerError.serviceFailure("Failed to move tabs.")
            }
            reconcileCurrentSession()
            // JavaScript reads the resulting Tab objects from WebKit so its
            // sensitive-property filtering and native identifiers remain intact.
            replyHandler([:], nil)
        } catch { replyHandler(nil, error) }
        return true
    }
}
