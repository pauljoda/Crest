import Foundation

enum BrowserPageExportError: LocalizedError {
    case pageUnavailable

    var errorDescription: String? {
        switch self {
        case .pageUnavailable:
            "There is no loaded page to export."
        }
    }
}
