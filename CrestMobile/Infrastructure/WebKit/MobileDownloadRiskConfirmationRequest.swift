import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

struct MobileDownloadRiskConfirmationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let assessment: DownloadRiskAssessment
    let sourceURL: URL?
    let spaceName: String
    /// The profile the download belongs to. Only windows browsing it present
    /// the request.
    let profileID: UUID

    init(
        id: UUID = UUID(),
        assessment: DownloadRiskAssessment,
        sourceURL: URL?,
        spaceName: String,
        profileID: UUID
    ) {
        self.id = id
        self.assessment = assessment
        self.sourceURL = sourceURL
        self.spaceName = spaceName
        self.profileID = profileID
    }

    var title: String {
        "Download “\(assessment.sanitizedFilename)”?"
    }

    var sourceLabel: String? {
        sourceURL?.host() ?? sourceURL?.absoluteString
    }

    var message: String {
        var paragraphs = assessment.reasons.map { String(localized: $0.message) }
        if let sourceLabel {
            paragraphs.append("Source: \(sourceLabel)")
        }
        paragraphs.append("This request belongs only to the \(spaceName) Space.")
        paragraphs.append("Open this file only if you trust its source.")
        return paragraphs.joined(separator: "\n\n")
    }
}
