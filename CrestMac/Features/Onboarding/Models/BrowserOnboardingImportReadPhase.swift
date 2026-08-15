import Foundation
import Observation

enum BrowserOnboardingImportReadPhase: Equatable {
    case idle
    case reading(id: UUID, application: BrowserImportApplication)

    var application: BrowserImportApplication? {
        switch self {
        case .idle:
            nil
        case .reading(_, let application):
            application
        }
    }

    var requestID: UUID? {
        switch self {
        case .idle:
            nil
        case .reading(let id, _):
            id
        }
    }
}
