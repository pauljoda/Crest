import Foundation

struct BrowserDownloadItem: Identifiable, Equatable, Sendable {

    let id: UUID
    let profileID: UUID
    let createdAt: Date
    var filename: String
    var destinationURL: URL?
    var progress: Double
    var state: BrowserDownloadItemState
    var riskAssessment: BrowserDownloadRiskAssessment?
}
