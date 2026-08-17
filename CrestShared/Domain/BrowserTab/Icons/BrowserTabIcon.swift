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
    ) -> BrowserTabIconAccent {
        siteTheme ?? extracted ?? .white
    }
}

enum BrowserTabIconMode: String, Codable, Equatable, Sendable {
    case automatic
    case pulled
    case emoji
}
