import SwiftUI

/// Site Controls on iPhone and iPad, for the page the window shows: the
/// window's commands run on it, as its palette and hardware keyboard run
/// them, and what only a phone or tablet offers, such as the site's desktop
/// version, Add to Home Screen and Hide Toolbar, is data. A command that runs
/// as Site Controls close, such as the share sheet, which UIKit presents only
/// once nothing else is going away, waits until they are gone. The window's
/// commands and downloads follow the window while Site Controls stay open.
@Observable
@MainActor
final class MobileSiteControls: SiteControlsPlatform {
    // MARK: - Variables

    let browser: BrowserStore
    let pages: MobileSelectedPageActionPort
    let mobilePage: MobileBrowserPage
    /// The window's commands, as its palette runs them, as the window last
    /// gave them.
    private(set) var commands: MobileBrowserCommandContext?
    /// The window's downloads list and how many downloads wait unseen, where
    /// the window shows a downloads badge, as the window last gave them.
    private(set) var downloadsAccess: MobileDownloadsMenuAccess?
    /// Where the control that opened Site Controls sits in the window, which
    /// a share sheet points at on iPad.
    private let source: CGRect?
    /// Hides the toolbar, where the window has one to hide.
    private let hideToolbar: (() -> Void)?
    private let close: @MainActor () -> Void
    /// Opens one of Site Controls' pages, for an action that shows its result
    /// there, such as the page's QR code.
    @ObservationIgnored var openSiteControlsPage: (@MainActor (SiteControlsPage) -> Void)?
    /// Whether Site Controls are going away, so a command waits for them.
    @ObservationIgnored private var isDismissing = false
    /// What runs once Site Controls are gone.
    @ObservationIgnored private var afterDismissalWork: [@MainActor () -> Void] = []

    var page: BrowserPlatformPage { mobilePage }
    var core: CrestCore { browser.core }
    var space: SpaceModel? { browser.shownSpace }
    var tab: TabStateModel? { pages.pageAssignment.flatMap { browser.shownSpace?.shownTab($0.tabID) } }
    var otherSpaceGroups: [[SpaceModel]] {
        let others = browser.spaceModels.filter { $0.id != mobilePage.spaceID }
        return others.isEmpty ? [] : [others]
    }
    var offersCertificates: Bool { false }
    var certificateReview: (@MainActor () -> Void)? { nil }
    var developerMode: SiteControlsDeveloperMode? { nil }
    var engineChoice: SiteControlsEngineChoice? { nil }
    var offersExtensions: Bool { false }
    var requestsDesktopSite: Bool? { mobilePage.isRequestingDesktopSite }

    // MARK: - Initializers

    init(
        browser: BrowserStore, pages: MobileSelectedPageActionPort, page: MobileBrowserPage,
        commands: MobileBrowserCommandContext?, source: CGRect?, hideToolbar: (() -> Void)?,
        downloadsAccess: MobileDownloadsMenuAccess?, dismiss: @escaping @MainActor () -> Void
    ) {
        self.browser = browser
        self.pages = pages
        mobilePage = page
        self.commands = commands
        self.source = source
        self.hideToolbar = hideToolbar
        self.downloadsAccess = downloadsAccess
        close = dismiss
    }

    // MARK: - Actions - Actions

    func state(of action: SiteControlAction) -> SiteControlActionState {
        switch action {
        case .share, .showQRCode:
            return SiteControlActionState(isAvailable: mobilePage.linkToCopy != nil)
        case .addToHomeScreen:
            return pages.canAddToHomeScreen ? SiteControlActionState() : .notOffered
        case .hideToolbar:
            return hideToolbar == nil ? .notOffered : SiteControlActionState()
        case .exportPDF, .saveWebArchive:
            return SiteControlActionState(isAvailable: pages.isAvailable)
        case .showTranslationControls:
            return SiteControlActionState(
                isAvailable: canRun(.toggleTranslationToolbar), isOn: commands?.isTranslationToolbarVisible == true)
        default:
            guard let command = action.command, let commands, MobileBrowserCommand.of(command) != nil,
                commands.isOffered(command)
            else { return .notOffered }
            return SiteControlActionState(isAvailable: canRun(command))
        }
    }

    func run(_ action: SiteControlAction) {
        let pages = pages
        let source = source
        switch action {
        case .share: afterDismissal { pages.sharePage(from: source) }
        case .showQRCode: openSiteControlsPage?(.qrCode)
        case .addToHomeScreen: afterDismissal { pages.addToHomeScreen(from: source) }
        case .hideToolbar:
            guard let hideToolbar else { return }
            afterDismissal { hideToolbar() }
        case .exportPDF: afterDismissal { pages.exportPDF(to: .files) }
        case .saveWebArchive: afterDismissal { pages.exportWebArchive(to: .files) }
        default:
            if let command = action.command { run(command) }
        }
    }

    func canRun(_ command: ShortcutCommand) -> Bool {
        guard let commands, let mobile = MobileBrowserCommand.of(command) else { return false }
        return commands.isOffered(command) && mobile.isAvailable(commands) && mobile.isEnabled(commands)
    }

    func run(_ command: ShortcutCommand) {
        guard let commands, let mobile = MobileBrowserCommand.of(command), mobile.isAvailable(commands) else { return }
        afterDismissal { mobile.run(commands) }
    }

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? { nil }

    // MARK: - Actions - Page

    func openPage(in space: SpaceModel) {
        guard let commands else { return }
        afterDismissal { commands.openPageInSpace(space.id) }
    }

    func toggleDesktopSite() {
        pages.togglePreferredContentMode()
    }

    func openSettings(_ destination: BrowserSettingsDestination) {
        let commands = commands
        afterDismissal { [browser] in
            guard let commands else {
                _ = browser.openSettings()
                return
            }
            commands.openSettings(destination)
        }
    }

    /// Follows the window's commands and downloads as it gives them anew.
    func follow(commands: MobileBrowserCommandContext?, downloadsAccess: MobileDownloadsMenuAccess?) {
        self.commands = commands
        self.downloadsAccess = downloadsAccess
    }

    func dismiss() {
        isDismissing = true
        close()
    }

    var showsDownloads: (@MainActor () -> Void)? {
        guard let open = downloadsAccess?.open else { return nil }
        return { [weak self] in self?.afterDismissal(open) }
    }

    var newDownloadCount: Int { downloadsAccess?.newItemCount ?? 0 }

    /// Runs what waited for Site Controls to go away, now that they have.
    func didDismiss() {
        let work = afterDismissalWork
        afterDismissalWork = []
        isDismissing = false
        for run in work { run() }
    }

    /// Runs `work` now, or once Site Controls are gone while they are going.
    private func afterDismissal(_ work: @escaping @MainActor () -> Void) {
        guard isDismissing else {
            work()
            return
        }
        afterDismissalWork.append(work)
    }
}
