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

    /// Posts a notice the first time a current, public, unlocked Space's download finishes.
    private func downloadChanged(_ download: DownloadState) {
        guard download.phase.isComplete, download.createdAt >= startedAt, let space = space(for: download),
            !isPrivate(space), !isLocked(space),
            announcedDownloadIDs.insert(download.id).inserted
        else { return }
        BrowserNoticeCenter.shared.post(.downloadFinished(download.filename))
    }

    /// Finds the Space that browses with the download's profile, if it still exists.
    private func space(for download: DownloadState) -> SpaceModel? {
        core?.state.workspaces.values.lazy.compactMap { workspace in
            workspace.spaces.models.first { $0.profileID == download.profileID }
        }.first
    }

    /// Whether the Space belongs to a private workspace.
    private func isPrivate(_ space: SpaceModel) -> Bool {
        core?.state.workspaces.values.contains { workspace in
            workspace.kind.isPrivate && workspace.spaces.models.contains { $0 === space }
        } == true
    }

    /// Whether the protected Space has no current core access grant.
    private func isLocked(_ space: SpaceModel) -> Bool {
        guard space.settings.requiresAuthentication else { return false }
        return core?.state.spaceAccess.first { $0.key.spaceID == space.id }?.value.isUnlocked != true
    }
}
