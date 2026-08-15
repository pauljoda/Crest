import CoreGraphics

enum BrowserPageZoomPolicy {
    static let levels: [CGFloat] = [
        0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3
    ]

    static func increased(from current: CGFloat) -> CGFloat {
        levels.first(where: { $0 > current + tolerance }) ?? levels[levels.count - 1]
    }

    static func decreased(from current: CGFloat) -> CGFloat {
        levels.last(where: { $0 < current - tolerance }) ?? levels[0]
    }

    static func percentageLabel(for zoom: CGFloat) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }

    private static let tolerance: CGFloat = 0.001
}
