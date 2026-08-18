struct BrowserDownloadRiskAssessment: Codable, Equatable, Sendable {
    let sanitizedFilename: String
    let reasons: [BrowserDownloadRiskReason]

    var requiresConfirmation: Bool {
        !reasons.isEmpty
    }

    /// User-initiated installers follow the platform's quarantine and
    /// Gatekeeper flow without an extra browser prompt. Filename deception and
    /// an executable type mismatch remain suspicious regardless of activation.
    func requiresConfirmation(isUserInitiated: Bool) -> Bool {
        if reasons.contains(.deceptiveFilename)
            || reasons.contains(.dangerousTypeMismatch)
        {
            return true
        }
        return reasons.contains(.executableOrInstaller) && !isUserInitiated
    }
}
