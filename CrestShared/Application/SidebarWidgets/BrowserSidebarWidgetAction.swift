import Foundation

/// Something a sidebar card offers. Each action carries how the widget that
/// offers it performs it: the software update card through its updater, the
/// Now Playing card through the media session store. An action a widget does
/// not offer does nothing there. An action the software update card shows as
/// a button carries how it shows it.
struct BrowserSidebarWidgetAction: Hashable, Sendable {
    // MARK: - Static Variables

    static let activateOwner = Self(name: "activateOwner")
    static let play = mediaSession(.play)
    static let pause = mediaSession(.pause)
    static let previousTrack = mediaSession(.previousTrack)
    static let nextTrack = mediaSession(.nextTrack)
    /// Widget-level only: muting is an element property, not a Media Session
    /// action a page can register a handler for.
    static let toggleMute = Self(name: "toggleMute") { store, session in
        store.toggleMute(of: session)
    }
    /// Hides this session's card until its tab plays again. Widget-level only.
    static let dismissMediaSession = Self(name: "dismissMediaSession") { store, session in
        store.dismissCard(of: session)
    }
    static let declineAutomaticUpdateChecks = Self(
        name: "declineAutomaticUpdateChecks", button: CardButton(priority: 0, title: "Not Now", symbol: "clock")
    ) {
        $0.chooseAutomaticChecks(false)
    }
    static let dismissExactUpdate = Self(
        name: "dismissExactUpdate",
        button: CardButton(
            priority: 1, title: "Skip", symbol: "forward.end", accessibilityLabel: "Skip This Version")
    ) { updater in
        // Sparkle persists `.skip` against the exact appcast build. Its own
        // app-scoped store is authoritative, and a newer build is therefore
        // offered again without Crest maintaining a competing dismissal key.
        updater.skipUpdate()
    }
    /// The card opens the release's page itself.
    static let viewUpdateInformation = Self(
        name: "viewUpdateInformation",
        button: CardButton(
            priority: 2, title: "View Release", symbol: "arrow.up.right", isProminent: true,
            opensReleasePage: true))
    static let installUpdate = Self(
        name: "installUpdate",
        button: CardButton(
            priority: 3, title: "Download", symbol: "arrow.down.circle", accessibilityLabel: "Download Update",
            isProminent: true)
    ) { $0.installUpdate() }
    static let installAndRelaunch = Self(
        name: "installAndRelaunch",
        button: CardButton(
            priority: 4, title: "Restart", symbol: "arrow.down.to.line", accessibilityLabel: "Restart and Update",
            isProminent: true)
    ) { $0.installAndRelaunchNow() }
    static let cancelUpdate = Self(
        name: "cancelUpdate", button: CardButton(priority: 5, title: "Cancel", symbol: "xmark")
    ) { $0.cancelCurrentOperation() }
    static let retryUpdateInstallation = Self(
        name: "retryUpdateInstallation",
        button: CardButton(
            priority: 6, title: "Retry", symbol: "arrow.clockwise", accessibilityLabel: "Try Quitting Again",
            isProminent: true)
    ) {
        $0.retryApplicationTermination()
    }
    static let enableAutomaticUpdateChecks = Self(
        name: "enableAutomaticUpdateChecks",
        button: CardButton(
            priority: 7, title: "Check Automatically", symbol: "arrow.trianglehead.2.clockwise.rotate.90",
            isProminent: true)
    ) {
        $0.chooseAutomaticChecks(true)
    }
    static let acknowledgeUpdateStatus = Self(
        name: "acknowledgeUpdateStatus", button: CardButton(priority: 8, title: "Dismiss", symbol: "xmark")
    ) { $0.acknowledge() }
    /// Hides the update card until the person checks for updates or Crest
    /// restarts. Widget-level only: the update itself carries on, and the
    /// card offers it from its corner rather than as a button.
    static let hideSoftwareUpdate = Self(name: "hideSoftwareUpdate") { $0.hide() }

    // MARK: - Types

    /// How the software update card shows an action as one of its buttons.
    struct CardButton: Sendable {
        /// Where the button stands among the card's others, lowest first.
        let priority: Int
        let title: LocalizedStringResource
        let symbol: String
        /// What VoiceOver reads and the pointer's help shows, when the title
        /// alone says less.
        var accessibilityLabel: LocalizedStringResource? = nil
        /// Whether the button is the card's primary one.
        var isProminent = false
        /// Whether the card opens the update's release page for it instead
        /// of performing it.
        var opensReleasePage = false
    }

    // MARK: - Variables

    let name: String
    /// How the software update card shows the action, or nil for one it
    /// shows no button for.
    let cardButton: CardButton?
    private let softwareUpdatePerformance: (@MainActor @Sendable (any BrowserSoftwareUpdateActionPerformer) -> Void)?
    private let nowPlayingPerformance:
        (@MainActor @Sendable (any BrowserNowPlayingActionPerformer, BrowserMediaSessionSnapshot) -> Void)?

    // MARK: - Initializers

    private init(name: String, button: CardButton? = nil) {
        self.name = name
        cardButton = button
        softwareUpdatePerformance = nil
        nowPlayingPerformance = nil
    }

    private init(
        name: String, button: CardButton? = nil,
        softwareUpdate: @escaping @MainActor @Sendable (any BrowserSoftwareUpdateActionPerformer) -> Void
    ) {
        self.name = name
        cardButton = button
        softwareUpdatePerformance = softwareUpdate
        nowPlayingPerformance = nil
    }

    private init(
        name: String,
        nowPlaying:
            @escaping @MainActor @Sendable (any BrowserNowPlayingActionPerformer, BrowserMediaSessionSnapshot)
            -> Void
    ) {
        self.name = name
        cardButton = nil
        softwareUpdatePerformance = nil
        nowPlayingPerformance = nowPlaying
    }

    // MARK: - Actions - Media sessions

    /// The card action that asks the page for one of its own Media Session
    /// actions.
    static func mediaSession(_ action: MediaSessionAction) -> Self {
        Self(name: "mediaSession.\(action)") { store, session in
            store.perform(action, on: session)
        }
    }

    // MARK: - Actions - Performing

    /// Performs the action on the software update card's updater.
    @MainActor
    func perform(on updater: any BrowserSoftwareUpdateActionPerformer) {
        softwareUpdatePerformance?(updater)
    }

    /// Performs the action on a Now Playing card's session.
    @MainActor
    func perform(on store: any BrowserNowPlayingActionPerformer, session: BrowserMediaSessionSnapshot) {
        nowPlayingPerformance?(store, session)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
