import CoreGraphics

/// How much chrome a settings page puts around its pane.
///
/// Most destinations get the readable, scrolling page with its own identity
/// header. Spaces runs a two-column layout edge to edge and names itself, so the
/// page steps out of the way; Shortcuts scrolls its own table.
struct BrowserSettingsPageLayout: Equatable {
    var scrollsContent = true
    var maximumContentWidth =
        BrowserSettingsVisualPolicy.maximumReadableContentWidth
    var contentHorizontalPadding = CrestSpacing.section
    var showsPageIdentity = true

    static let readable = BrowserSettingsPageLayout()
    static let selfScrolling = BrowserSettingsPageLayout(scrollsContent: false)
    static let fullBleed = BrowserSettingsPageLayout(
        scrollsContent: false,
        maximumContentWidth: .infinity,
        contentHorizontalPadding: 0,
        showsPageIdentity: false
    )

    static func page(
        for destination: BrowserSettingsDestination
    ) -> BrowserSettingsPageLayout {
        switch destination {
        case .spaces: .fullBleed
        case .shortcuts, .featureFlags: .selfScrolling
        case .general, .links, .sync, .privacy, .passwords, .extensions,
            .advanced:
            .readable
        }
    }
}
