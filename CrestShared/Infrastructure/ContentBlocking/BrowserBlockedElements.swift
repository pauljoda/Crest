import Foundation

/// What the person blocked with Block Element on one page's site, and showing
/// it again, as Safari's Show Hidden Items does: the core drops the site's
/// rules from the person's filters, and once the rules without them are in
/// force the page reloads to show what they hid.
@MainActor
struct BrowserBlockedElements {
    // MARK: - Static Variables

    /// The longest the page waits for the rules without the site's before it
    /// reloads anyway.
    private static let settling: Duration = .seconds(10)
    private static let poll: Duration = .milliseconds(100)

    // MARK: - Variables

    let core: CrestCore
    let pageURL: URL?

    /// Whether the person blocked anything on the page's site.
    var exist: Bool {
        guard let address = webAddress else { return false }
        return (try? core.query(PageBlocksElements(pageURL: address))) ?? false
    }

    private var webAddress: String? {
        guard let pageURL, ["http", "https"].contains(pageURL.scheme?.lowercased() ?? "") else { return nil }
        return pageURL.absoluteString
    }

    // MARK: - Actions - Showing

    /// Shows what the person blocked on the site again: the core drops the
    /// site's rules, `refresh` puts the rules without them in force once the
    /// core has converted them, and `reload` shows the page anew. Answers
    /// whether anything was blocked there.
    @discardableResult
    func show(refresh: () async -> Void, reload: () -> Void) async -> Bool {
        guard let address = webAddress else { return false }
        let previous = core.state.contentRuleLists
        guard (try? core.send(UnblockElements(pageURL: address)))?.isEmpty == false else { return false }
        let deadline = ContinuousClock.now + Self.settling
        while core.state.contentRuleLists == previous, ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.poll)
        }
        await refresh()
        reload()
        return true
    }
}
