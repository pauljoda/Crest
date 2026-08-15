enum BrowserDownloadRiskReason: String, Codable, CaseIterable, Hashable, Sendable {
    case executableOrInstaller
    case deceptiveFilename
    case dangerousTypeMismatch
}
