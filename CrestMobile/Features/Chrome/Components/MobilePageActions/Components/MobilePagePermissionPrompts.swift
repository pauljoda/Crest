import SwiftUI

/// Asks for the shown page's site permissions from the control that opens the
/// page's actions, pointing at it.
struct MobilePagePermissionPrompts: ViewModifier {
    let pages: any MobilePageActions

    func body(content: Content) -> some View {
        content
            .pagePermissionHost(pages.activePage?.sitePermissionRequests)
            .crestPopover(
                item: Binding {
                    pages.activePage?.sitePermissionRequests.current
                } set: { request in
                    if request == nil && pages.activePage?.sitePermissionRequests.current != nil {
                        pages.activePage?.sitePermissionRequests.cancelAll()
                    }
                }
            ) { request in
                if let controller = pages.activePage?.sitePermissionRequests {
                    BrowserPagePermissionPrompt(request: request, controller: controller)
                        .presentationCompactAdaptation(.popover)
                }
            }
    }
}
