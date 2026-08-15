import Foundation

struct BrowserSyncVersion: Codable, Equatable, Comparable, Sendable {
    let logicalClock: UInt64
    let deviceID: UUID

    static func < (lhs: BrowserSyncVersion, rhs: BrowserSyncVersion) -> Bool {
        if lhs.logicalClock != rhs.logicalClock {
            return lhs.logicalClock < rhs.logicalClock
        }
        return lhs.deviceID.uuidString < rhs.deviceID.uuidString
    }
}
