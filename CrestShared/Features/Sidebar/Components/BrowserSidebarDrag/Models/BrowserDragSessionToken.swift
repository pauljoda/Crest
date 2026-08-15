import Foundation

struct BrowserDragSessionToken: Equatable, Sendable {
    let rawValue: UUID

    init(generation: UInt64) {
        let value = generation.bigEndian
        rawValue = withUnsafeBytes(of: value) { bytes in
            UUID(
                uuid: (
                    0x43, 0x52, 0x45, 0x53, 0x54, 0x44, 0x52, 0x41,
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7]
                )
            )
        }
    }
}
