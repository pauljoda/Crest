import Foundation

protocol BrowserExtensionIconDecoding<DecodedIcon>: Sendable {
    associatedtype DecodedIcon: Sendable

    func decode(
        _ data: Data,
        maximumPixelSize: Int
    ) async -> DecodedIcon?
}
