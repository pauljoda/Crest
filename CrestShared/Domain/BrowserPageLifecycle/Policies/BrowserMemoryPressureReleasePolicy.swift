import Foundation

struct BrowserMemoryPressureReleasePolicy: Equatable, Sendable {
    static func releaseLimit(
        for level: BrowserMemoryPressureLevel,
        eligiblePageCount: Int,
        platform: BrowserMemoryPressurePlatform
    ) -> Int {
        guard eligiblePageCount > 0 else { return 0 }
        switch (platform, level) {
        case (.desktop, .warning):
            return 1
        case (.desktop, .critical):
            return max(1, (eligiblePageCount + 1) / 2)
        case (.mobile, .warning):
            return 0
        case (.mobile, .critical):
            return 1
        }
    }
}
