import Foundation

/// A fixed-size SHA-256 content identity for encoded extension artwork.
struct BrowserExtensionIconContentIdentifier: Hashable, Sendable {
    static let digestByteCount = 32

    let encodedByteCount: Int
    private let firstWord: UInt64
    private let secondWord: UInt64
    private let thirdWord: UInt64
    private let fourthWord: UInt64

    init(
        encodedByteCount: Int,
        firstWord: UInt64,
        secondWord: UInt64,
        thirdWord: UInt64,
        fourthWord: UInt64
    ) {
        self.encodedByteCount = encodedByteCount
        self.firstWord = firstWord
        self.secondWord = secondWord
        self.thirdWord = thirdWord
        self.fourthWord = fourthWord
    }
}

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

struct BrowserExtensionIconRequestIdentity: Hashable, Sendable {
    let extensionID: String?
    let spaceID: SpaceID
    let contentIdentifier: BrowserExtensionIconContentIdentifier?
    let maximumPixelSize: Int
}

struct BrowserExtensionIconRequest: Sendable {

    static let maximumPixelSizeLimit = 512

    let extensionID: String?
    let spaceID: SpaceID
    let payload: BrowserExtensionIconPayload?
    let maximumPixelSize: Int

    var identity: BrowserExtensionIconRequestIdentity {
        BrowserExtensionIconRequestIdentity(
            extensionID: extensionID,
            spaceID: spaceID,
            contentIdentifier: payload?.contentIdentifier,
            maximumPixelSize: maximumPixelSize
        )
    }

    init(
        extensionID: String?,
        spaceID: SpaceID,
        payload: BrowserExtensionIconPayload?,
        maximumPixelSize: Int
    ) {
        self.extensionID = extensionID
        self.spaceID = spaceID
        self.payload = payload
        self.maximumPixelSize = min(
            max(1, maximumPixelSize),
            Self.maximumPixelSizeLimit
        )
    }
}
