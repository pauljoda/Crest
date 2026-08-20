import SwiftUI

/// What the compact shell puts *over* its sidebar: the three sheets it owns and
/// the foreground the selected Space's branding asks for.
///
/// The sidebar's own confirmation and its utility bookkeeping moved into the
/// shared root; what is left is presentation this shell alone has, so the state
/// behind it lives in the shell that presents it.
struct MobileBrowserSidebarPresentationConfiguration {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let dataDeleter: any BrowserSpaceDataDeleting
    let spaceAccess: BrowserSpaceAccessController
    let selectedColorScheme: ColorScheme
    let showsPasswords: Binding<Bool>
    let showsSettings: Binding<Bool>
    let presentedSpaceSheet: Binding<MobileBrowserSidebarSpaceSheet?>
    let selectedSpaceAssignment: BrowserSpaceRuntimeAssignment?
    let selectTab: (TabID) -> Void
    let openURL: (URL) -> Void
}
