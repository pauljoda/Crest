struct BrowserDownloadRiskAssessment: Codable, Equatable, Sendable {
    let sanitizedFilename: String
    let reasons: [BrowserDownloadRiskReason]

    var requiresConfirmation: Bool {
        !reasons.isEmpty
    }
}
