import SwiftUI

// MARK: - Types

/// How one of Site Controls' actions stands for the page now, as the platform
/// that runs it says.
struct SiteControlActionState: Equatable {
    /// An action the page cannot run now, which a tile and More Actions show
    /// dimmed.
    static let unavailable = SiteControlActionState(isAvailable: false)
    /// An action the platform does not offer for the page at all, such as a
    /// move to another engine while only one is registered.
    static let notOffered = SiteControlActionState(isOffered: false, isAvailable: false)

    /// Whether the platform offers the action for the page, so the lists show
    /// it.
    var isOffered = true
    /// Whether the page can run the action now.
    var isAvailable = true
    /// Whether what the action turns on is on, such as a pinned tab.
    var isOn = false
    /// What the platform calls the action now in place of its own title, such
    /// as the engine a page would move to; nil for its own.
    var title: LocalizedStringResource?
    /// What a tile calls the action now in place of its short title.
    var shortTitle: LocalizedStringResource?
}

/// Developer Mode while it is on for the page, which waits under the actions
/// with a way to turn it off.
struct SiteControlsDeveloperMode {
    /// Whether the page's address turned it on by itself, as a local
    /// development address does.
    let isAutomatic: Bool
    let turnOff: @MainActor () -> Void
}

/// The engines a site can open in, offered while the device registered more
/// than one.
struct SiteControlsEngineChoice {
    /// Every registered engine, in the order the menu lists them.
    let engines: [EngineKind]
    /// The engine the page runs in now, which the site's later pages open in.
    let current: EngineKind
    /// Moves the page to `engine` and keeps the site there.
    let remember: @MainActor (EngineKind) -> Void
    /// Moves the page to `engine` this once.
    let move: @MainActor (EngineKind) -> Void
    /// The name of the engine's logo in the app's assets, which the menu
    /// draws beside its name; nil for none.
    let logo: @MainActor (EngineKind) -> String?
}

// MARK: - Platform

/// What Site Controls asks of the platform that shows them: the page they are
/// about, how the platform runs Crest's commands on it, and the parts only
/// some platforms or engines have, which are data here so the component itself
/// stays the same everywhere.
@MainActor
protocol SiteControlsPlatform: AnyObject {
    /// The page Site Controls are about.
    var page: BrowserPlatformPage { get }
    var core: CrestCore { get }
    /// The page's Space, which the header's chip names.
    var space: SpaceModel? { get }
    /// The page's tab, whose icon leads the header; nil for a page no tab
    /// holds, such as a Quick Window's.
    var tab: TabStateModel? { get }
    /// The window's other Spaces the page can open in, in the groups the menu
    /// separates.
    var otherSpaceGroups: [[SpaceModel]] { get }

    /// How `action` stands for the page now.
    func state(of action: SiteControlAction) -> SiteControlActionState
    /// Runs `action` on the page.
    func run(_ action: SiteControlAction)
    /// Whether `command` can run on the page now.
    func canRun(_ command: ShortcutCommand) -> Bool
    /// Runs `command` on the page, as its menu item or keys do.
    func run(_ command: ShortcutCommand)
    /// The keys `command` runs by on this device, as the person set them.
    func shortcut(for command: ShortcutCommand) -> BrowserShortcut?

    /// Opens the page's address in `space`, as a Quick Window there.
    func openPage(in space: SpaceModel)
    /// Whether the platform shows a secure page's certificate, so a secure
    /// page without one to show is not called secure.
    var offersCertificates: Bool { get }
    /// Shows the page's certificate, or nil where the platform has no panel
    /// for one or the engine gave none to show.
    var certificateReview: (@MainActor () -> Void)? { get }
    /// Developer Mode while it is on for the page; nil while it is off or
    /// where the platform has none.
    var developerMode: SiteControlsDeveloperMode? { get }
    /// The engines the site can open in, or nil with only one.
    var engineChoice: SiteControlsEngineChoice? { get }
    /// Whether the page's engine has extensions, whose tiles and page the
    /// shell gives ``SiteControlsView``.
    var offersExtensions: Bool { get }
    /// Whether the page asks for the site's desktop version, where the page's
    /// toggles offer the choice, as a phone's do; nil elsewhere.
    var requestsDesktopSite: Bool? { get }
    /// Asks for the site's desktop version, or its mobile one again.
    func toggleDesktopSite()
    /// Opens Settings at `destination`.
    func openSettings(_ destination: BrowserSettingsDestination)
    /// Puts Site Controls away.
    func dismiss()
    /// Shows the device's own downloads list in place of the Downloads page,
    /// where the platform has one that also marks new downloads seen; nil for
    /// the page.
    var showsDownloads: (@MainActor () -> Void)? { get }
    /// How many downloads of the page's Space the person has not seen yet,
    /// which the Downloads row names while none is under way.
    var newDownloadCount: Int { get }
}

extension SiteControlsPlatform {
    var showsDownloads: (@MainActor () -> Void)? { nil }
    var newDownloadCount: Int { 0 }
}
