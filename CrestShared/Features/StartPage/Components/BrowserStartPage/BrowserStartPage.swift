import SwiftUI

/// The surface a tab shows before it has a page.
///
/// Both shells draw the same thing here — the mark, the title, the private
/// browsing notice, and the embedded command palette — so this is that surface
/// once. What a shell wants of its own arrives as data: its
/// ``BrowserStartPageLayout``, the appearance its header reads over Space
/// branding, the focus request its address field raises, and the
/// ``BrowserStartPagePromotion`` that grows that field into the palette.
///
/// The tab is named explicitly rather than read off the Space because Split
/// View renders one of these per card, so the surface cannot assume it is
/// speaking for the selected tab. Every action still routes through
/// `BrowserCommandPaletteActionPolicy`, which answers "unavailable" for a card
/// that is not the focused one.
struct BrowserStartPage: View {
    let space: BrowserSpace?
    let isPrivateBrowsing: Bool
    let selectedTabID: TabID?
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    let openURL: (BrowserTabRuntimeAssignment, URL) -> Bool
    let isCommandPaletteObscured: Bool
    let layout: BrowserStartPageLayout
    /// Bumped by a shell whose address field asks the palette to take focus
    /// again. Absent where the shell has no such field.
    var focusRequest: Int? = nil
    var promotion: BrowserStartPagePromotion? = nil
    /// The appearance the header reads its text tone from, for a shell that
    /// draws the header over Space branding. `nil` inherits the environment.
    var headerColorScheme: ColorScheme? = nil

    var body: some View {
        ZStack {
            BrowserStartPageBackground(page: self)
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("start-page-surface")
    }

    @ViewBuilder
    private var content: some View {
        if layout.scrollsContent {
            ScrollView {
                BrowserStartPageStack(page: self)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            BrowserStartPageStack(page: self)
        }
    }
}
