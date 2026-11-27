import Foundation

/// Shared page behavior owned once for both macOS (`BrowserPage`) and
/// iOS/iPadOS (`MobileBrowserPage`).
extension BrowserPlatformPage {
    // MARK: - Actions - Navigation & Popups

    /// Records that web content opened this page and that WebKit still owes it a
    /// navigation. Only a page owner adopting a popup calls this.
    func markOpenedAsPopup() {
        wasOpenedAsPopup = true
        isAwaitingPopupNavigation = true
    }

    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    // MARK: - Actions - Sharing & Links

    /// The page's address as copying or sharing it hands it out.
    var linkToCopy: BrowserCopiedLink? {
        live.documentURL.map(downloadCenter.core.linkToCopy)
    }

    /// Copies the page's address, without its trackers while Super Copy is on.
    @discardableResult
    func copyPageLink() -> Bool {
        BrowserPageLinkClipboard.copy(linkToCopy)
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        BrowserPageLinkClipboard.copyMarkdown(linkToCopy, title: live.title)
    }

    // MARK: - Actions - Zoom

    @discardableResult
    func zoomIn() -> Bool {
        guard allowsPageZoomChange else { return false }
        return setTemporaryPageZoom(pageZoom.pageZoomIncreased)
    }

    @discardableResult
    func zoomOut() -> Bool {
        guard allowsPageZoomChange else { return false }
        return setTemporaryPageZoom(pageZoom.pageZoomDecreased)
    }

    @discardableResult
    func resetZoom() -> Bool {
        guard allowsPageZoomChange else { return false }
        hasTemporaryPageZoomOverride = false
        return setPageZoom(defaultPageZoom)
    }

    /// Updates this page's global baseline without discarding a temporary zoom
    /// chosen through the page commands. A manually zoomed page rejoins the
    /// baseline when Reset is used, when recreation makes a new page, or when
    /// the newly selected default already equals its temporary value.
    @discardableResult
    func applyDefaultPageZoom(_ zoom: CGFloat) -> Bool {
        let normalized = BrowserDefaultPageZoomStore.normalized(zoom)
        defaultPageZoom = normalized
        if hasTemporaryPageZoomOverride {
            if pageZoom.matchesPageZoom(normalized) {
                hasTemporaryPageZoomOverride = false
            }
            return false
        }
        return setPageZoom(normalized)
    }

    private func setTemporaryPageZoom(_ zoom: CGFloat) -> Bool {
        let changed = setPageZoom(zoom)
        hasTemporaryPageZoomOverride = !pageZoom.matchesPageZoom(defaultPageZoom)
        return changed
    }

    // MARK: - Actions - Content Blocking

    /// Lets the person point at an element of the page to block on its site
    /// from now on, starting from what they last right-clicked when
    /// `fromContextMenu`. Answers whether the picker started.
    @discardableResult
    func pickElementToBlock(fromContextMenu: Bool = false) async -> Bool {
        await cosmeticFilters?.pickElement(fromContextMenu: fromContextMenu) ?? false
    }

    // MARK: - Actions - Credentials & Autofill

    var isCredentialAccessEnabled: Bool { credentialSession.isEnabled }
    var credentialFillRequest: BrowserCredentialFillRequest? { credentialState.fillRequest }
    var credentialSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.saveCandidate }
    var credentialHeldSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.heldSaveCandidate }
    var autofillSaveCandidate: BrowserAutofillSaveCandidate? { credentialState.autofillSaveCandidate }
    var credentialKeyPress: BrowserCredentialKeyPress? { credentialState.keyPress }

    /// The login the page last filled, whose code a code step offers first.
    var lastFilledCredentialID: UUID? { credentialState.lastFilledCredentialID }

    func dismissAutofillSaveCandidate() {
        credentialState.dismissAutofillSaveCandidate()
    }

    func dismissCredentialFillRequest() {
        credentialState.dismissFillRequest()
    }

    func dismissCredentialSaveCandidate() {
        credentialState.dismissSaveCandidate()
    }

    /// Not Now: the offer goes, and the key in the address field keeps it.
    func declineCredentialSaveCandidate() {
        credentialState.holdSaveCandidate()
    }

    func reofferCredentialSaveCandidate() {
        credentialState.reofferHeldSaveCandidate()
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        credentialSession.setEnabled(isEnabled)
    }

    func fillCredential(_ credential: BrowserCredential, for requestID: UUID) async throws {
        guard let evaluate = credentialEvaluator else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fill(credential, for: requestID, evaluate: evaluate)
    }

    func fillAutofillValues(_ values: [BrowserAutofillValue], for requestID: UUID) async throws {
        guard let evaluate = credentialEvaluator else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fillValues(values, for: requestID, evaluate: evaluate)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID) async throws {
        guard let evaluate = credentialEvaluator else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fillGeneratedPassword(password, for: requestID, evaluate: evaluate)
    }

    func credentialFormUsername(for requestID: UUID) async -> String? {
        guard let evaluate = credentialEvaluator else { return nil }
        return await credentialSession.currentUsername(for: requestID, evaluate: evaluate)
    }

    func holdCredentialKeys(_ hold: Bool, for requestID: UUID) async {
        guard let evaluate = credentialEvaluator else { return }
        await credentialSession.holdKeys(hold, for: requestID, evaluate: evaluate)
    }
}
