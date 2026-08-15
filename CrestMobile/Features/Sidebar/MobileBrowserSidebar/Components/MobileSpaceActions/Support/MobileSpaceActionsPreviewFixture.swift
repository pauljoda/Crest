import Foundation

struct MobileSpaceActionsPreviewFixture {
    static let downloads = [
        BrowserDownloadItem(
            id: UUID(
                uuid: (
                    0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            ),
            profileID: UUID(
                uuid: (
                    0x42, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            ),
            createdAt: Date(timeIntervalSince1970: 0),
            filename: "Crest Guide.pdf",
            destinationURL: nil,
            progress: 0.6,
            state: .downloading,
            riskAssessment: nil
        )
    ]
}
