import Foundation

struct BrowserPeekSourcePresentation: Codable, Equatable, Hashable, Sendable {
    let normalizedMinX: Double
    let normalizedMinY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double
    let normalizedTouchX: Double
    let normalizedTouchY: Double
    let label: String

    init(
        normalizedMinX: Double,
        normalizedMinY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double,
        normalizedTouchX: Double? = nil,
        normalizedTouchY: Double? = nil,
        label: String
    ) {
        let minX = Self.normalizedValue(normalizedMinX)
        let minY = Self.normalizedValue(normalizedMinY)
        let width = Self.normalizedValue(normalizedWidth)
        let height = Self.normalizedValue(normalizedHeight)
        self.normalizedMinX = minX
        self.normalizedMinY = minY
        self.normalizedWidth = min(width, 1 - minX)
        self.normalizedHeight = min(height, 1 - minY)
        self.normalizedTouchX = Self.normalizedValue(
            normalizedTouchX ?? minX + self.normalizedWidth / 2
        )
        self.normalizedTouchY = Self.normalizedValue(
            normalizedTouchY ?? minY + self.normalizedHeight / 2
        )
        self.label = String(
            label
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(160)
        )
    }

    static func resolved(
        _ sourcePresentation: BrowserPeekSourcePresentation?
    ) -> BrowserPeekSourcePresentation {
        sourcePresentation ?? BrowserPeekSourcePresentation(
            normalizedMinX: 0.5,
            normalizedMinY: 0.5,
            normalizedWidth: 0,
            normalizedHeight: 0,
            normalizedTouchX: 0.5,
            normalizedTouchY: 0.5,
            label: "Browser center"
        )
    }

    private static func normalizedValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
