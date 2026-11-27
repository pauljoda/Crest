import Foundation

extension BrowserPeekRequest {
    // MARK: - Static Variables

    /// A page's outline in grey bars, drawn in the reader's light or dark, so
    /// a sample Peek shows its size without a site to load.
    private static let sampleMarkup: String = {
        guard let url = Bundle.main.url(forResource: "PeekSample", withExtension: "html") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    /// The sample page's address, the markup itself.
    private static var sampleURL: URL {
        let encoded = sampleMarkup.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: "data:text/html;charset=utf-8,\(encoded)") ?? URL(string: "about:blank")!
    }

    // MARK: - Initializers

    /// A Peek of a sample page over the Settings tab `tab`, which a person
    /// opens to try the size they chose.
    static func sample(over tab: BrowserTabRuntimeAssignment) -> BrowserPeekRequest {
        BrowserPeekRequest(
            url: sampleURL,
            sourceTabID: tab.tabID,
            sourceTitle: String(localized: "Settings"),
            spaceAssignment: tab.spaceAssignment,
            trigger: .sample
        )
    }
}
