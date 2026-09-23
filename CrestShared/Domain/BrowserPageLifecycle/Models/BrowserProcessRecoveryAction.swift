/// Raw values are the core's `residency.process_recovery` spellings.
enum BrowserProcessRecoveryAction: String, Decodable, Equatable {
    case reload
    case showFailure
}
