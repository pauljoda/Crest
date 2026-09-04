import AppKit
import SwiftUI

/// Hands the SwiftUI trigger a way to open the same menu the pointer opens, so
/// VoiceOver and Full Keyboard Access still reach the switcher.
@MainActor
final class BrowserExtensionSidebarSwitcherPresenter {
    var present: (() -> Void)?
}

/// Places the AppKit menu owner over the SwiftUI trigger.
struct BrowserExtensionSidebarSwitcherMenuAnchor: NSViewRepresentable {
    let presenter: BrowserExtensionSidebarSwitcherPresenter
    let makeModel: () -> BrowserExtensionSidebarSwitcherMenuModel
    let select: (BrowserExtensionServiceClientID) -> Void
    let presentingChanged: (Bool) -> Void
    let hoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> BrowserExtensionSidebarSwitcherMenuAnchorView {
        let view = BrowserExtensionSidebarSwitcherMenuAnchorView()
        attach(to: view)
        return view
    }

    func updateNSView(_ nsView: BrowserExtensionSidebarSwitcherMenuAnchorView, context: Context) {
        attach(to: nsView)
    }

    private func attach(to view: BrowserExtensionSidebarSwitcherMenuAnchorView) {
        view.makeModel = makeModel
        view.select = select
        view.presentingChanged = presentingChanged
        view.hoverChanged = hoverChanged
        presenter.present = { [weak view] in view?.presentMenu() }
    }
}
