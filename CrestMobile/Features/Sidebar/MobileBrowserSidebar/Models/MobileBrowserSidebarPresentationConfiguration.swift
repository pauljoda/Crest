import SwiftUI

/// The sidebar's utility sheets and Space foreground.
struct MobileBrowserSidebarPresentationConfiguration {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectedColorScheme: ColorScheme
    let showsPasswords: Binding<Bool>
    let presentedSpaceSheet: Binding<MobileBrowserSidebarSpaceSheet?>
    let selectedSpaceAssignment: BrowserSpaceRuntimeAssignment?
    let selectTab: (TabID) -> Void
    let openURL: (URL) -> Void
}
