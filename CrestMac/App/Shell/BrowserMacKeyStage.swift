/// Where a key down is when the shell is offered it: on its way to a focused
/// page, on its way to one of Crest's own focused views, or at the menu bar,
/// which gets what no view took and what a page let go.
struct BrowserMacKeyStage: Equatable {
    // MARK: - Static Variables

    static let beforePage = BrowserMacKeyStage(pageSeesFirst: true, viewSeesFirst: true)
    static let beforeCrestView = BrowserMacKeyStage(pageSeesFirst: false, viewSeesFirst: true)
    static let menuBar = BrowserMacKeyStage(pageSeesFirst: false, viewSeesFirst: false)

    // MARK: - Variables

    /// A focused page is still to see the key.
    let pageSeesFirst: Bool
    /// A focused view, a page or one of Crest's fields, is still to see the
    /// key, so text editing keys wait for it.
    let viewSeesFirst: Bool
}
