import Foundation

/// Native transfers stay in their engine. Crest owns the destination, record and
/// user decisions; UI code never needs a Chromium or WebKit download object.
struct BrowserEngineDownloadID: Hashable {
    let engine: BrowserEngineImplementation.Family
    let profileID: UUID
    let value: String
}

struct BrowserEngineDownloadUpdate {
    enum State: Equatable {
        case preparing, downloading, finished, canceled
        case failed(String)
        case awaitingApproval(token: String, message: String)
    }
    let id: BrowserEngineDownloadID
    let filename: String
    let destination: URL?
    let bytesReceived: Int64
    let totalBytes: Int64
    let isPaused: Bool
    let state: State
    var createdAt: Date = .now
    var isRestored = false
}

@MainActor
protocol BrowserEngineDownloadControlling: AnyObject {
    func cancelDownload(_ id: BrowserEngineDownloadID)
    /// Remove engine history and unfinished temporary data, keeping saved files.
    func removeDownload(_ id: BrowserEngineDownloadID)
    /// The adapter must recheck this exact warning before applying the decision.
    func approveDownload(_ id: BrowserEngineDownloadID, warningToken: String)
}
