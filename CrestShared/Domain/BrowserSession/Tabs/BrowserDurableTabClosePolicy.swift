import Foundation

enum BrowserDurableTabClosePolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case resumeLastLocation
    case returnToSavedURL

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .resumeLastLocation: "Resume last location"
        case .returnToSavedURL: "Return to saved URL"
        }
    }
}
