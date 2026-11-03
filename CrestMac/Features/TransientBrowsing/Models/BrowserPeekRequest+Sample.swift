import Foundation

extension BrowserPeekRequest {
    // MARK: - Static Variables

    /// A page's outline in grey bars, drawn in the reader's light or dark, so
    /// a sample Peek shows its size without a site to load.
    private static let sampleMarkup = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark"><style>
        body{margin:0;padding:56px;background:Canvas}main{max-width:720px;margin:auto}
        i{display:block;height:14px;margin:16px 0;border-radius:7px;background:color-mix(in srgb,CanvasText 12%,transparent)}
        .title{width:55%;height:36px;margin-bottom:36px;border-radius:10px;background:color-mix(in srgb,CanvasText 22%,transparent)}
        .short{width:68%}.image{height:240px;margin:36px 0;border-radius:16px}
        </style></head><body><main><i class="title"></i><i></i><i></i><i class="short"></i><i class="image"></i>
        <i></i><i></i><i></i><i class="short"></i></main></body></html>
        """

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
