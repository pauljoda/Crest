import Foundation

struct BrowserExtensionIconPayload: Equatable, Sendable {
    static let maximumEncodedByteCount = 1_048_576

    let data: Data
    let contentIdentifier: BrowserExtensionIconContentIdentifier

    var isValidForDecoding: Bool {
        !data.isEmpty
            && data.count <= Self.maximumEncodedByteCount
            && contentIdentifier.encodedByteCount == data.count
    }
}
