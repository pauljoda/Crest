import UniformTypeIdentifiers
import WebKit

/// Which addresses and responses a phone or tablet downloads instead of
/// showing in the tab: files that are not web pages, such as a PDF or a Word
/// document, which a tab could only show and not keep.
extension MobileBrowserPage {
    // MARK: - Static Variables

    private static let webSchemes: Set<String> = ["http", "https"]
    /// What a tab shows as it is: web pages and any other text, such as plain
    /// text, JSON or a feed, and audio and video, which play in the tab.
    private static let shownInTabTypes: [UTType] = [.text, .audiovisualContent]

    // MARK: - Actions - Files

    /// Whether `navigationResponse` brings a file of a type the system knows
    /// and the tab does not show as a page.
    static func isFile(_ navigationResponse: WKNavigationResponse) -> Bool {
        guard navigationResponse.canShowMIMEType, let mimeType = navigationResponse.response.mimeType,
            let type = UTType(mimeType: mimeType)
        else { return false }
        return isFile(type)
    }

    /// Whether `url` is a web address whose name ends in a file's type, as a
    /// link to a PDF or a Word document is. One with a query is left to the
    /// server, since sharing services answer `report.pdf?dl=0` with a page.
    static func namesFile(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme), url.query == nil,
            !url.pathExtension.isEmpty, let type = UTType(filenameExtension: url.pathExtension)
        else { return false }
        return isFile(type)
    }

    private static func isFile(_ type: UTType) -> Bool {
        type.isDeclared && !shownInTabTypes.contains { type.conforms(to: $0) }
    }
}
