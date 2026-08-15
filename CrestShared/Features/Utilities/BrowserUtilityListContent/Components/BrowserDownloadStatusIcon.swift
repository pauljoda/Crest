import SwiftUI

struct BrowserDownloadStatusIcon: View {
    let item: BrowserDownloadItem

    var body: some View {
        switch item.state {
        case .preparing:
            ProgressView().controlSize(.small)
        case .awaitingApproval:
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
        case .downloading:
            ZStack {
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(item.progress, 0.02))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Download Progress")
            .accessibilityValue(
                Text(
                    BrowserDownloadProgressPolicy.normalized(item.progress),
                    format: .percent.precision(.fractionLength(0))
                )
            )
        case .finished:
            Image(systemName: "doc.fill")
        case .blockedAutomaticDownload:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
        case .canceled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}

#Preview("Download Status Icons", traits: .fixedLayout(width: 220, height: 64)) {
    HStack(spacing: 20) {
        BrowserDownloadStatusIcon(
            item: BrowserUtilityListPreviewFixture.preparingDownload
        )
        BrowserDownloadStatusIcon(
            item: BrowserUtilityListPreviewFixture.activeDownload
        )
        BrowserDownloadStatusIcon(
            item: BrowserUtilityListPreviewFixture.finishedDownload
        )
        BrowserDownloadStatusIcon(
            item: BrowserUtilityListPreviewFixture.failedDownload
        )
    }
    .frame(height: 24)
    .padding()
}
