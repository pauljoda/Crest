import Foundation

enum BrowserTabIconAccentResolver {
    static func resolve(
        siteTheme: BrowserTabIconAccent?,
        extracted: BrowserTabIconAccent?
    ) -> BrowserTabIconAccent {
        siteTheme ?? extracted ?? .white
    }
}
