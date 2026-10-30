import Foundation

/// Tells the helper which tab is in front or went away, as Apple's extension
/// does for Chrome's tabs. It is not encrypted and has no reply, so it is not
/// a request.
struct ApplePasswordsTabEventMessage {
    // MARK: - Actions - Encoding

    /// - Parameter tabID: The number the helper knows the tab by.
    static func encoded(tabID: Int, event: ApplePasswordsTabEvent) throws -> Data {
        try JSONEncoder().encode(Body(number: ApplePasswordsCommand.tabEvent.number, tabID: tabID, event: event))
    }

    // MARK: - Types

    private struct Body: Encodable {
        let number: Int
        let tabID: Int
        let event: ApplePasswordsTabEvent

        private enum CodingKeys: String, CodingKey {
            case number = "cmd"
            case tabID = "tabId"
            case event
        }
    }
}
