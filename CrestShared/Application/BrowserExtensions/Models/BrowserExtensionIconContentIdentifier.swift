/// A fixed-size SHA-256 content identity for encoded extension artwork.
///
/// The encoded byte count participates in equality as an additional collision
/// discriminator without retaining the encoded payload in cache keys.
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
