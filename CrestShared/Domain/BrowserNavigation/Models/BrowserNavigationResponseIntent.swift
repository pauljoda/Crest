import Foundation

enum BrowserNavigationResponseIntent: Equatable {
    case display
    case download

    static func classify(
        canShowMIMEType: Bool,
        response: URLResponse?
    ) -> BrowserNavigationResponseIntent {
        if !canShowMIMEType || requestsDownload(response) {
            return .download
        }
        return .display
    }

    private static func requestsDownload(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse,
            let disposition = response.value(
                forHTTPHeaderField: "Content-Disposition"
            )
        else {
            return false
        }
        let directive =
            disposition
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return directive == "attachment"
    }
}
