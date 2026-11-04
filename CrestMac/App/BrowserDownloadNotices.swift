import Foundation

/// Confirms each download that finishes while the app is running, once.
@MainActor
final class BrowserDownloadNotices {
    // MARK: - Variables

    private weak var core: CrestCore?
    private var announcedDownloadIDs: Set<UUID> = []
    private let startedAt: Date

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
        startedAt = .now
        core.followDownloads(self) { [weak self] in self?.downloadChanged($0) }
    }

    // MARK: - Actions - Downloads

    private func downloadChanged(_ download: DownloadState) {
        guard download.phase.isComplete, download.createdAt >= startedAt, !isPrivate(download),
            announcedDownloadIDs.insert(download.id).inserted
        else { return }
        BrowserNoticeCenter.shared.post(.downloadFinished(download.filename))
    }

    private func isPrivate(_ download: DownloadState) -> Bool {
        core?.state.workspaces.values.contains { workspace in
            workspace.kind.isPrivate && workspace.spaces.models.contains { $0.profileID == download.profileID }
        } == true
    }
}
