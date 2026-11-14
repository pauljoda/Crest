import WebKit

/// Runs the content filter's scriptlets in a WebKit page's own world, before
/// the page's scripts: a main-frame navigation installs, as one user script,
/// what the core answers for the site it goes to, in place of the previous
/// site's. Only a page that owns its user content controller runs them; a
/// popup shares its opener's.
@MainActor
final class BrowserPageScriptletSession {
    // MARK: - Variables

    /// The scriptlets for a URL, or an empty script for none.
    private let scriptlets: @MainActor (URL) -> String
    private var installed: WKUserScript?

    // MARK: - Initializers

    init(scriptlets: @escaping @MainActor (URL) -> String) {
        self.scriptlets = scriptlets
    }

    /// The scriptlets of a page of `spaceID`, as `core` answers them.
    convenience init(core: CrestCore, spaceID: UUID) {
        self.init { url in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return "" }
            return (try? core.query(PageScriptlets(spaceID: spaceID, url: url.absoluteString))) ?? ""
        }
    }

    // MARK: - Actions - Navigation

    /// Gives a main-frame navigation to `url` the scriptlets of its site before
    /// the page loads it.
    func navigating(to url: URL, in controller: WKUserContentController) {
        let source = scriptlets(url)
        guard installed != nil || !source.isEmpty else { return }
        // WebKit removes user scripts only all at once, so the others go back.
        let others = controller.userScripts.filter { $0 !== installed }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        installed = nil
        guard !source.isEmpty else { return }
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
        controller.addUserScript(script)
        installed = script
    }
}
