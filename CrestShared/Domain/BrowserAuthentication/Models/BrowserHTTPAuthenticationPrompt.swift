struct BrowserHTTPAuthenticationPrompt: Equatable, Sendable {
    let descriptor: BrowserHTTPAuthenticationDescriptor
    let suggestedUsername: String?
    let allowsSaving: Bool
}
