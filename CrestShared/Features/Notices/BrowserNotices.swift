import Observation

/// The notice a window shows at its top. A newer notice replaces one still
/// showing, and each leaves once it has been up as long as it lasts. Every
/// layer that draws the window's notices reads the one showing here, so a
/// sheet that opens over the window shows it too, and none shows it again
/// after it left.
@Observable
@MainActor
final class BrowserNotices {
    // MARK: - Variables

    /// The notice showing now, or nil while none shows.
    private(set) var shown: BrowserNotice? {
        get { observed(\.shownStorage, as: \.shown) }
        set { publish(newValue, into: \.shownStorage, as: \.shown) }
    }
    @ObservationIgnored private var shownStorage: BrowserNotice?
    /// Counts the notices shown, so only the latest one's time running out
    /// puts a notice away.
    @ObservationIgnored private var revision = 0

    // MARK: - Actions - Showing

    /// Shows `notice`, replacing any notice already showing, for as long as
    /// it lasts.
    func show(_ notice: BrowserNotice) {
        revision &+= 1
        let shownRevision = revision
        shown = notice
        Task { [weak self] in
            try? await Task.sleep(for: notice.duration)
            guard let self, revision == shownRevision else { return }
            shown = nil
        }
    }

    /// Puts `notice` away early, if it is the one showing, once what it
    /// reports no longer holds.
    func dismiss(_ notice: BrowserNotice) {
        guard shown == notice else { return }
        revision &+= 1
        shown = nil
    }
}

extension BrowserNotices: BrowserStoreFirstObservable {}
