import Foundation

struct BrowserTabIconAccent: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    static let white = BrowserTabIconAccent(red: 1, green: 1, blue: 1)
}

enum BrowserTabIconAccentResolver {
    static func resolve(
        siteTheme: BrowserTabIconAccent?,
        extracted: BrowserTabIconAccent?
    ) -> BrowserTabIconAccent? {
        if let siteTheme, isDistinctive(siteTheme) { return siteTheme }
        return extracted
    }

    private static func isDistinctive(_ color: BrowserTabIconAccent) -> Bool {
        let brightest = max(color.red, color.green, color.blue)
        let darkest = min(color.red, color.green, color.blue)
        // Page chrome often declares neutral or subtly tinted system surfaces.
        // Defer those to the favicon, whose own neutral colors remain valid.
        return brightest - darkest >= 0.08 && brightest >= 0.18 && darkest <= 0.90
    }
}

enum BrowserTabIconMode: String, Codable, Equatable, Sendable {
    case automatic
    case pulled
    case emoji
}
