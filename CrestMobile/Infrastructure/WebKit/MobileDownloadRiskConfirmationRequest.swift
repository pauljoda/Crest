import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

struct MobileDownloadRiskConfirmationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let assessment: BrowserDownloadRiskAssessment
    let sourceURL: URL?
    let spaceName: String

    init(
        id: UUID = UUID(),
        assessment: BrowserDownloadRiskAssessment,
        sourceURL: URL?,
        spaceName: String
    ) {
        self.id = id
        self.assessment = assessment
        self.sourceURL = sourceURL
        self.spaceName = spaceName
    }

    var title: String {
        "Download “\(assessment.sanitizedFilename)”?"
    }

    var sourceLabel: String? {
        sourceURL?.host() ?? sourceURL?.absoluteString
    }

    var message: String {
        var paragraphs = assessment.reasons.map(\.message)
        if let sourceLabel {
            paragraphs.append("Source: \(sourceLabel)")
        }
        paragraphs.append("This request belongs only to the \(spaceName) Space.")
        paragraphs.append("Open this file only if you trust its source.")
        return paragraphs.joined(separator: "\n\n")
    }
}
