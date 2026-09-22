/// Projection of the core's risk assessment: the filename a download is saved
/// under and every reason it looks dangerous. The core decides the reasons and
/// whether the person must confirm.
struct BrowserDownloadRiskAssessment: Equatable, Sendable {
    let sanitizedFilename: String
    let reasons: [BrowserDownloadRiskReason]
}

/// A risk assessment together with the core's answer to whether this download,
/// given how it started, needs the person's confirmation before it continues.
struct BrowserDownloadRiskVerdict: Equatable, Sendable {
    let assessment: BrowserDownloadRiskAssessment
    let requiresConfirmation: Bool
}
