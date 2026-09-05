import Foundation

/// A native tab is addressed by its primary-window index and, when visible to
/// the extension, its URL. The broker rechecks both before any mutation.
struct BrowserExtensionTabTarget: Equatable, Sendable {
    let index: Int
    let url: String?

    init(message: [String: Any]) throws {
        guard let number = message["tabIndex"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
            number.doubleValue.rounded(.towardZero) == number.doubleValue,
            number.doubleValue >= 0, number.doubleValue <= Double(Int32.max),
            message["url"] == nil || message["url"] is String
        else { throw BrowserExtensionTabGroupBrokerError.invalidRequest }
        index = number.intValue
        url = message["url"] as? String
    }

    func resolve(in space: BrowserExtensionSpaceState, liveTabs: Set<TabID>) throws -> TabID {
        guard let tab = space.tabs.first(where: { $0.index == index }), liveTabs.contains(tab.id),
            BrowserExtensionTabIdentity.urlMatches(reported: url, state: tab.url)
        else { throw BrowserExtensionTabGroupBrokerError.staleTab }
        return tab.id
    }
}
