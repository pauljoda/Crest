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
                guard model.isSelected && !focusGate.browserChromeOwnsFocus else { return .ignored }
                dismiss()
                return .handled
            }
            .background {
                BrowserPeekKeyboardMonitor(
                    dismiss: dismiss,
                    installsMonitor: installsKeyboardMonitor && model.isSelected && !focusGate.browserChromeOwnsFocus
                )
                .frame(width: 0, height: 0)
            }
    }
}
