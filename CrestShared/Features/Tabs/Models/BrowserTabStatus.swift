import SwiftUI

// MARK: - Types

/// What a tab wears for one status now: its symbol and tint, what it says,
/// what pressing it offers, and how it dresses the whole tab. A mark with one
/// action is a button that runs it; one with several opens a menu of them.
/// Sound is blue, as a playing tab is elsewhere on the Mac; sharing is purple,
/// as the system marks a screen being shared.
@MainActor
struct BrowserTabStatusMark: Equatable {
    // MARK: - Static Variables

    /// The page plays sound someone can hear.
    static let playing = Self(
        symbol: "speaker.wave.2.fill",
        tint: .blue,
        title: LocalizedStringResource("Playing Audio", comment: "A tab's mark while its page plays sound."),
        actions: [.mute],
        surface: .equalizer
    )

    /// The page still plays, with its sound muted.
    static let muted = Self(
        symbol: "speaker.slash.fill",
        tint: .blue,
        title: LocalizedStringResource("Muted", comment: "A tab's mark while its page plays with its sound muted."),
        actions: [.unmute]
    )

    /// Another page shows this tab.
    static let shared = Self(
        symbol: SitePermission.screenSharing.symbol,
        tint: .purple,
        title: LocalizedStringResource("Shared", comment: "A tab's mark while another page shares it."),
        actions: [.goToSharingTab, .stopSharing],
        surface: .outline
    )

    /// The tab's page shows another tab.
    static let sharing = Self(
        symbol: "rectangle.on.rectangle",
        tint: .purple,
        title: LocalizedStringResource("Sharing a Tab", comment: "A tab's mark while its page shares another tab."),
        actions: [.goToSharedTab, .stopSharing]
    )

    // MARK: - Variables

    let symbol: String

    /// The color the mark's badge is filled with, so each kind of status reads
    /// at a glance.
    let tint: SystemTint

    /// What the mark says the tab is doing: its tooltip, and what VoiceOver
    /// reads for it.
    let title: LocalizedStringResource

    /// What the mark offers, in the order its menu lists them.
    let actions: [BrowserTabStatusAction]

    /// How the mark dresses the whole tab, when it does.
    let surface: BrowserTabStatusSurface?

    // MARK: - Initializers

    private init(
        symbol: String, tint: SystemTint, title: LocalizedStringResource, actions: [BrowserTabStatusAction],
        surface: BrowserTabStatusSurface? = nil
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.actions = actions
        self.surface = surface
    }

    // MARK: - Equatable

    /// A mark is its symbol; the rest follows from it.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.symbol == rhs.symbol }
}

/// Something a tab's page is doing that the tab wears a mark for while it
/// lasts. Each status reads the page and answers with the mark it shows now,
/// or none. `all` is the order a row draws the marks in and the order a pinned
/// tile picks its one badge from, so adding a status is adding an instance.
@MainActor
struct BrowserTabStatus {
    // MARK: - Static Variables

    /// Another page shows this tab.
    static let shared = Self { tab in tab.isShared ? .shared : nil }

    /// The tab's page shows another tab.
    static let sharing = Self { tab in tab.isSharing ? .sharing : nil }

    /// The page plays sound, heard or muted. An engine may still call muted
    /// playback audible, so muting decides before audibility does.
    static let audio = Self { tab in
        guard let session = tab.mediaSession else { return nil }
        if session.isMuted {
            return session.isAudible || session.playbackState == .playing ? .muted : nil
        }
        return session.isAudible ? .playing : nil
    }

    static let all = [shared, sharing, audio]

    // MARK: - Variables

    /// The mark the tab wears for the status now, or nil while its page is not
    /// doing it. Reading it observes what it reads of the page.
    let mark: @MainActor (BrowserTabStatusSource) -> BrowserTabStatusMark?

    // MARK: - Initializers

    private init(mark: @escaping @MainActor (BrowserTabStatusSource) -> BrowserTabStatusMark?) {
        self.mark = mark
    }

    // MARK: - Actions - Reading

    /// The marks the tab wears now, in the order of `all`.
    static func marks(of tab: BrowserTabStatusSource) -> [BrowserTabStatusMark] {
        all.compactMap { $0.mark(tab) }
    }
}
