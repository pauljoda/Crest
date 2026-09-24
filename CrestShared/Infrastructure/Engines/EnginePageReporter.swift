import Foundation

/// Tells the core what one page's engine saw its navigations and its icon do.
/// Every engine binding feeds it the engine's own callbacks, so a page reports
/// the same events whichever engine hosts it:
///
/// - A navigation that loads a new document starts, commits, then finishes
///   with the title it settled on, or fails.
/// - A move within the document, such as `history.pushState` or a fragment,
///   starts and commits when the address changes, and finishes once the
///   page's title settles (see `titleSettleInterval`). A move while a new
///   document is still loading belongs to that load, which finishes it.
/// - An icon is reported when the engine finds one for the document, and
///   again when the page's theme changes the color behind it.
///
/// The core decides what each event records; this only decides when the
/// engine's callbacks amount to one.
@MainActor
final class EnginePageReporter {
    // MARK: - Variables

    /// How long a page's title must hold after a move within its document
    /// before the move finishes. Sites that route in script, such as video,
    /// mail and code hosts, change the address first and set the new page's
    /// title a moment later, sometimes through an interim one such as
    /// "Loading…". Finishing at once would record the previous page's title.
    static let titleSettleInterval: Duration = .milliseconds(500)

    /// The longest a move within the document waits for its title to settle,
    /// counted from the move, so a page whose title never stops changing, such
    /// as one counting unread mail, still records.
    static let titleSettleLimit: Duration = .seconds(2)

    private let report: @MainActor (any EngineEvent, Data?) -> Void
    /// The page's title as the engine shows it now.
    private let currentTitle: @MainActor () -> String
    private let pageID: UUID
    /// The document's address as last reported.
    private var documentURL: URL?
    /// A navigation to a new document started and has not finished or failed.
    private var isLoadingDocument = false
    /// The move within the document waiting for its title, with the latest
    /// moment it may finish and the timer that finishes it.
    private var settling: (url: URL, deadline: ContinuousClock.Instant, timer: Task<Void, Never>)?
    /// The image the engine found for the document, and where.
    private var icon: (data: Data, url: URL)?
    /// The color the page's theme puts behind its icon.
    private var accent: TabIconAccent?

    // MARK: - Initializers

    /// A reporter for `pageID` that hands each event to `report`, with the
    /// image a `PageIconChanged` names, and reads the page's title from
    /// `title` when a move within the document settles.
    init(
        pageID: UUID, title: @escaping @MainActor () -> String,
        report: @escaping @MainActor (any EngineEvent, Data?) -> Void
    ) {
        self.pageID = pageID
        currentTitle = title
        self.report = report
    }

    /// A reporter that reports through the engine hosting `page`.
    convenience init(page: CorePage, title: @escaping @MainActor () -> String) {
        self.init(pageID: page.id, title: title) { [weak page] event, icon in page?.report(event, icon: icon) }
    }

    // MARK: - Actions - Navigation

    /// A navigation to a new document began, toward `url` when the engine
    /// knows it yet.
    func started(_ url: URL?) {
        cancelSettling()
        isLoadingDocument = true
        report(NavigationStarted(pageID: pageID, url: url?.absoluteString ?? "", sameDocument: false), nil)
    }

    /// The new document took effect at `url`, without the icon of the one it
    /// replaced.
    func committed(_ url: URL) {
        cancelSettling()
        documentURL = url
        icon = nil
        report(NavigationCommitted(pageID: pageID, url: url.absoluteString, sameDocument: false), nil)
    }

    /// The new document finished loading at `url`, titled `title`.
    func finished(_ url: URL, title: String?) {
        cancelSettling()
        isLoadingDocument = false
        documentURL = url
        report(NavigationFinished(pageID: pageID, url: url.absoluteString, title: title ?? ""), nil)
    }

    /// The navigation failed and its document records nothing.
    func failed(_ url: URL?, error: NavigationError) {
        cancelSettling()
        isLoadingDocument = false
        report(NavigationFailed(pageID: pageID, url: url?.absoluteString, error: error), nil)
    }

    /// The navigation stopped without failing, as one that became a download
    /// or was cancelled does, so no new document is loading.
    func interrupted() {
        isLoadingDocument = false
    }

    /// The page's address changed without a new document: a move within the
    /// one it shows. It finishes once the title settles, unless a new
    /// document is loading, whose own finish covers it.
    func movedWithinDocument(to url: URL) {
        guard url != documentURL else { return }
        documentURL = url
        report(NavigationStarted(pageID: pageID, url: url.absoluteString, sameDocument: true), nil)
        report(NavigationCommitted(pageID: pageID, url: url.absoluteString, sameDocument: true), nil)
        guard !isLoadingDocument else { return }
        cancelSettling()
        let deadline = ContinuousClock.now + Self.titleSettleLimit
        settling = (url, deadline, settle(url, at: min(ContinuousClock.now + Self.titleSettleInterval, deadline)))
    }

    /// The page's title changed, which restarts the wait of a move within the
    /// document, never past its limit.
    func titleChanged() {
        guard let pending = settling else { return }
        pending.timer.cancel()
        settling = (
            pending.url, pending.deadline,
            settle(pending.url, at: min(ContinuousClock.now + Self.titleSettleInterval, pending.deadline))
        )
    }

    private func settle(_ url: URL, at instant: ContinuousClock.Instant) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do { try await Task.sleep(until: instant, clock: .continuous) } catch { return }
            guard let self, self.settling?.url == url else { return }
            self.settling = nil
            self.report(
                NavigationFinished(pageID: self.pageID, url: url.absoluteString, title: self.currentTitle()), nil)
        }
    }

    private func cancelSettling() {
        settling?.timer.cancel()
        settling = nil
    }

    // MARK: - Actions - Icon

    /// The engine found `data` as the icon of the document at `url`.
    func foundIcon(_ data: Data?, at url: URL?) {
        guard let data, !data.isEmpty, let url else { return }
        icon = (data, url)
        reportIcon()
    }

    /// The page's theme puts `accent` behind its icon.
    func themeChanged(_ accent: BrowserTabIconAccent?) {
        let accent = accent.map { TabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) }
        guard accent != self.accent else { return }
        self.accent = accent
        reportIcon()
    }

    private func reportIcon() {
        guard let icon else { return }
        report(PageIconChanged(pageID: pageID, url: icon.url.absoluteString, accent: accent), icon.data)
    }
}
