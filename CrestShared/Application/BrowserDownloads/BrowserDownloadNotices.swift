import Foundation

/// Confirms each download that finishes while the app is running, once.
@MainActor
final class BrowserDownloadNotices {
    // MARK: - Variables

    private weak var core: CrestCore?
    private weak var access: BrowserSpaceAccessController?
    private var announcedDownloadIDs: Set<UUID> = []
    private let startedAt: Date
    /// Opens a finished download where the platform shows files, which a
    /// notice offers as Open; nil offers none.
    var open: (@MainActor (DownloadState) -> Void)?

    // MARK: - Initializers

    init(core: CrestCore, access: BrowserSpaceAccessController) {
        self.core = core
        self.access = access
        startedAt = .now
        core.followDownloads(self) { [weak self] in self?.downloadChanged($0) }
    }

    // MARK: - Actions - Downloads

    /// Posts a notice once when a download of an unlocked, non-private Space finishes.
    private func downloadChanged(_ download: DownloadState) {
        guard download.phase.isComplete, download.createdAt >= startedAt, let access else { return }
        let matches = spaces(for: download)
        guard !matches.isEmpty, matches.allSatisfy({ !access.isLocked($0) }),
            announcedDownloadIDs.insert(download.id).inserted
        else { return }
        let opening = open.map { open in
            { @MainActor [weak self] in
                // A Space locked since the notice showed keeps its file.
                guard let self, let access = self.access,
                    self.spaces(for: download).allSatisfy({ !access.isLocked($0) })
                else { return }
                open(download)
            }
        }
        BrowserNoticeCenter.shared.post(.downloadFinished(download.filename, open: opening))
    }

    /// Every non-private Space browsing with the download's profile.
    private func spaces(for download: DownloadState) -> [SpaceModel] {
        core?.state.workspaces.values.filter { !$0.kind.isPrivate }.flatMap { $0.spaces.models }.filter {
            $0.profileID == download.profileID
        } ?? []
    }
}
