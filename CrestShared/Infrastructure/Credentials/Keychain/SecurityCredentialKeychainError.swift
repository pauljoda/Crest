enum SecurityCredentialKeychainError: Error, Equatable, Sendable {
    case unexpectedResult
    case status(Int32)
}
