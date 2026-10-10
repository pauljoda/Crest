import Foundation

/// What a tab's page is doing with sound when there is something to mark:
/// sound coming out, or playback someone muted. Each state carries its
/// symbol, how it reads to assistive technology, and what pressing its mark
/// does.
struct BrowserTabAudio: Hashable, Sendable {
    // MARK: - Static Variables

    /// The page plays sound someone can hear.
    static let audible = Self(
        symbol: "speaker.wave.2.fill",
        label: LocalizedStringResource(
            "Playing audio", comment: "Tooltip and accessibility value for a tab's mark while it plays sound."),
        actionName: LocalizedStringResource(
            "Mute tab", comment: "Accessibility label for a tab's audio mark that mutes the tab.")
    )

    /// Nothing is heard, but the page still plays with its sound muted.
    static let muted = Self(
        symbol: "speaker.slash.fill",
        label: LocalizedStringResource(
            "Muted", comment: "Tooltip and accessibility value for a tab's mark while its playback is muted."),
        actionName: LocalizedStringResource(
            "Unmute tab", comment: "Accessibility label for a tab's audio mark that unmutes the tab.")
    )

    // MARK: - Variables

    let symbol: String
    /// What the mark says the tab is doing.
    let label: LocalizedStringResource
    /// What pressing the mark does.
    let actionName: LocalizedStringResource

    // MARK: - Initializers

    private init(symbol: String, label: LocalizedStringResource, actionName: LocalizedStringResource) {
        self.symbol = symbol
        self.label = label
        self.actionName = actionName
    }

    /// The state a tab's published session puts it in, or `nil` while it
    /// makes no sound worth marking. An engine may still call muted playback
    /// audible, so muting decides before audibility does.
    init?(session: BrowserMediaSessionSnapshot) {
        if session.isMuted {
            guard session.isAudible || session.playbackState == .playing else { return nil }
            self = .muted
        } else {
            guard session.isAudible else { return nil }
            self = .audible
        }
    }

    // MARK: - Hashable

    /// A state is its symbol; the strings follow from it.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.symbol == rhs.symbol }

    func hash(into hasher: inout Hasher) { hasher.combine(symbol) }
}
