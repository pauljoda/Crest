import Foundation

extension CoreState {
    func apply(_ change: DownloadUpdated) {
        if let index = downloads.firstIndex(where: { $0.id == change.download.id }) {
            downloads[index] = change.download
        } else {
            downloads.insert(change.download, at: min(max(change.position, 0), downloads.count))
        }
    }

    func apply(_ change: DownloadsRemoved) {
        let removed = Set(change.downloadIDs)
        downloads.removeAll { removed.contains($0.id) }
    }
}
