/// A risk assessment together with the core's answer to whether this download,
/// given how it started, needs the person's confirmation before it continues.
struct BrowserDownloadRiskVerdict: Equatable, Sendable {
    let assessment: DownloadRiskAssessment
    let requiresConfirmation: Bool
}
