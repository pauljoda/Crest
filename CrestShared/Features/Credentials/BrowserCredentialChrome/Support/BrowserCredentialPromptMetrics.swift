import CoreGraphics

/// How wide a credential prompt is allowed to be.
enum BrowserCredentialPromptWidth: Equatable, Sendable {
    /// Pinned to one exact width. A panel floating over the page has no
    /// container to take its width from, so it decides its own.
    case fixed(CGFloat)

    /// As wide as the container allows, up to this much.
    case bounded(CGFloat)

    /// Whatever the container gives it.
    case flexible
}

/// The surface a shell draws a credential prompt on.
enum BrowserCredentialPromptSurfaceStyle: Equatable, Sendable {
    /// A rounded, stroked panel lifted off the page it floats over.
    case panel

    /// A band across the width of the content, closed by a divider.
    case band
}

/// The drawn geometry of the credential prompts, resolved once per shell rather
/// than spelled out by each fork of a prompt.
///
/// Every prompt holds the same anatomy everywhere — a title row with a close
/// control, an optional cross-origin notice, the prompt's own content, and its
/// failures. What changes between shells is the surface under it, how much room
/// it may claim, and whether its rows have to be aimed at with a finger.
struct BrowserCredentialPromptMetrics: Equatable, Sendable {
    let surfaceStyle: BrowserCredentialPromptSurfaceStyle

    let horizontalPadding: CGFloat

    let verticalPadding: CGFloat

    /// The width a fill prompt — suggestions or strong password — claims.
    let fillPromptWidth: BrowserCredentialPromptWidth

    /// The band the saved-password list is kept inside, or `nil` where the list
    /// simply grows the prompt.
    ///
    /// A pointer shell floats a panel that can be as tall as its content. A
    /// touch shell's prompt pushes the page down, so the list scrolls instead.
    let suggestionListMaximumHeight: CGFloat?

    /// The room a suggestion row keeps above and below itself.
    let suggestionRowVerticalPadding: CGFloat

    /// The height a suggestion row claims, or `nil` where the row keeps the
    /// height its content gives it.
    let suggestionRowMinimumHeight: CGFloat?

    /// The height the loading and empty states claim, so the prompt does not
    /// resize as the vault answers, or `nil` where they size to their text.
    let suggestionStateMinimumHeight: CGFloat?

    /// A pointer shell: a fixed-width panel floating over the page, rows sized
    /// by their content, and a list that grows the panel.
    static let pointer = BrowserCredentialPromptMetrics(
        surfaceStyle: .panel,
        horizontalPadding: CrestSpacing.medium,
        verticalPadding: CrestSpacing.medium,
        fillPromptWidth: .fixed(360),
        suggestionListMaximumHeight: nil,
        suggestionRowVerticalPadding: 5,
        suggestionRowMinimumHeight: nil,
        suggestionStateMinimumHeight: nil
    )

    /// A touch shell: a band across the top of the page, full 44pt targets, and
    /// a list that scrolls rather than pushing the page further down.
    ///
    /// The targets are literals rather than `CrestLayout.minimumHitTarget`, for
    /// the same reason `BrowserFindBarMetrics.touch`'s are: this profile is
    /// compared against from a suite hosted on macOS, where that token resolves
    /// to the pointer shell's 28, and a touch control still has to be 44.
    static let touch = BrowserCredentialPromptMetrics(
        surfaceStyle: .band,
        horizontalPadding: CrestSpacing.large,
        verticalPadding: CrestSpacing.medium,
        fillPromptWidth: .flexible,
        suggestionListMaximumHeight: 176,
        suggestionRowVerticalPadding: 0,
        suggestionRowMinimumHeight: 44,
        suggestionStateMinimumHeight: 44
    )

    /// The profile a shell draws its credential prompts with.
    ///
    /// Touch decides it for the same reason it decides the find bar's: a prompt
    /// is a column of hit targets before it is a panel, so its sizing follows
    /// the least precise input the shell accepts.
    static func resolve(
        _ capabilities: BrowserInteractionCapabilities
    ) -> BrowserCredentialPromptMetrics {
        capabilities.supportsTouch ? .touch : .pointer
    }

    // MARK: - Anatomy both shells agree on

    /// The gap between the prompt's stacked parts.
    static let contentSpacing = CrestSpacing.small

    /// The gap between the header's symbol, its titles, and its close control.
    static let headerSpacing: CGFloat = 9

    /// The gap between a header's title and the origin beneath it.
    static let headerTextSpacing: CGFloat = 1

    /// The least room kept between a header's titles and its close control.
    static let headerSpacerLength = CrestSpacing.small

    /// The frame a prompt's own controls claim.
    static let controlHitTarget: CGFloat = 44

    static let suggestionRowSpacing: CGFloat = 10

    static let suggestionRowSpacerLength: CGFloat = 10

    /// The panel's corner, stroke, and lift. A band draws none of them, and
    /// neither shell draws the lift once the reader has asked for reduced
    /// transparency.
    static let cornerRadius = CrestRadius.control
    static let strokeWidth: CGFloat = 0.5
    static let shadowOpacity = CrestOpacity.controlShadow
    static let shadowRadius: CGFloat = 14
    static let shadowOffset: CGFloat = 6
}
