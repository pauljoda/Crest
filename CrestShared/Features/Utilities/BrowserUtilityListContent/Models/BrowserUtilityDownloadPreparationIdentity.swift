import Foundation

/// The fields that can change download membership, grouping, search results,
/// text, or available actions. Progress is intentionally row-local and does
/// not require rebuilding the section model.
struct BrowserUtilityDownloadPreparationIdentity: Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    let createdAt: Date
    let filename: String
    let destinationURL: URL?
    let state: BrowserDownloadItemState
    let riskAssessment: BrowserDownloadRiskAssessment?

    init(_ item: BrowserDownloadItem) {
        id = item.id
        profileID = item.profileID
        createdAt = item.createdAt
        filename = item.filename
        destinationURL = item.destinationURL
        state = item.state
        riskAssessment = item.riskAssessment
    }
}
