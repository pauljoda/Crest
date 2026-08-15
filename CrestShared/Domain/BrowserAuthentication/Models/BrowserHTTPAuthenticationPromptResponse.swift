struct BrowserHTTPAuthenticationPromptResponse:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let username: String
    let password: String
    let shouldSave: Bool

    var description: String {
        "BrowserHTTPAuthenticationPromptResponse(username: \(username), password: <redacted>, shouldSave: \(shouldSave))"
    }

    var debugDescription: String { description }
}
