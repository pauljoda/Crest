import SwiftUI

struct BrowserPeekInputLifecycleModifier: ViewModifier {
    let model: BrowserPeekModel
    let dismiss: () -> Void
    let installsKeyboardMonitor: Bool

    init(
        model: BrowserPeekModel,
        dismiss: @escaping () -> Void,
        installsKeyboardMonitor: Bool = true
    ) {
        self.model = model
        self.dismiss = dismiss
        self.installsKeyboardMonitor = installsKeyboardMonitor
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.browserWebFocusRestorationGate) private var focusGate
    @Environment(\.browserWebFocusWindow) private var focusWindow

    /// Whether the window's chrome, or this Peek not being the one in use,
    /// holds keyboard focus rather than the Peek's page.
    private var browserChromeOwnsFocus: Bool {
        focusGate.browserChromeOwnsFocus || focusWindow?.chromeOwnsFocus == true
    }

    func body(content: Content) -> some View {
        content
            .onDisappear(perform: model.releaseForDisappearance)
            .onChange(of: scenePhase) { _, phase in
                model.setActive(phase == .active)
            }
            .onChange(of: model.isSelected) {
                model.setActive(scenePhase == .active)
            }
            .onKeyPress(.escape) {
                guard model.isSelected && !browserChromeOwnsFocus else { return .ignored }
                dismissFindOrPeek()
                return .handled
            }
            .background {
                BrowserPeekKeyboardMonitor(
                    dismiss: dismissFindOrPeek,
                    installsMonitor: installsKeyboardMonitor && model.isSelected && !browserChromeOwnsFocus
                )
                .frame(width: 0, height: 0)
            }
    }

    // MARK: - Actions - Dismissal

    /// Escape closes the Peek's find bar first, then the Peek.
    private func dismissFindOrPeek() {
        if let page = model.page, page.isFindPresented {
            page.dismissFind()
        } else {
            dismiss()
        }
    }
}
