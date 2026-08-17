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

    func body(content: Content) -> some View {
        content
            .onDisappear(perform: model.releaseForDisappearance)
            .onChange(of: scenePhase) { _, phase in
                model.setActive(phase == .active)
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            .background {
                BrowserPeekKeyboardMonitor(
                    dismiss: dismiss,
                    installsMonitor: installsKeyboardMonitor
                )
                .frame(width: 0, height: 0)
            }
    }
}
