import Foundation

/// Confirms each download that finishes while the app is running, once, and
/// offers to open it on a shell that can.
@MainActor
final class BrowserDownloadNotices {
    // MARK: - Variables

    private weak var core: CrestCore?
    private weak var access: BrowserSpaceAccessController?
    private var announcedDownloadIDs: Set<UUID> = []
    private let startedAt: Date
    private let open: (@MainActor (DownloadState) -> Void)?

    // MARK: - Initializers

    init(
        core: CrestCore, access: BrowserSpaceAccessController,
        open: (@MainActor (DownloadState) -> Void)? = nil
    ) {
        self.core = core
        self.access = access
        self.open = open
        startedAt = .now
        core.followDownloads(self) { [weak self] in self?.downloadChanged($0) }
    }

    // MARK: - Actions - Downloads

    /// Posts a notice once when a download of an unlocked, non-private Space finishes.
    private func downloadChanged(_ download: DownloadState) {
        guard download.phase.isComplete, download.createdAt >= startedAt, isInUnlockedSpaces(download),
            announcedDownloadIDs.insert(download.id).inserted
        else { return }
        BrowserNoticeCenter.shared.post(.downloadFinished(download.filename, open: opener(for: download)))
    }

    private func opener(for download: DownloadState) -> (@MainActor () -> Void)? {
        guard let open else { return nil }
        // The notice outlives the moment it was posted, and its Space may
        // lock before the person taps Open.
        return { [weak self] in
            guard let self, isInUnlockedSpaces(download) else { return }
            open(download)
        }
    }

    private func isInUnlockedSpaces(_ download: DownloadState) -> Bool {
        guard let access else { return false }
        let matches = spaces(for: download)
        return !matches.isEmpty && matches.allSatisfy { !access.isLocked($0) }
    }

    /// Every non-private Space browsing with the download's profile.
    private func spaces(for download: DownloadState) -> [SpaceModel] {
        core?.state.workspaces.values.filter { !$0.kind.isPrivate }.flatMap { $0.spaces.models }.filter {
            $0.profileID == download.profileID
        } ?? []
    }
}
