import Observation

enum BrowserStrongPasswordOperationPhase: Equatable, Sendable {
    case idle
    case working
    case failed
}
