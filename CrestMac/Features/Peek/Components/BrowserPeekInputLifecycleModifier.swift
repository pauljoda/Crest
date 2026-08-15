import SwiftUI

struct BrowserPeekInputLifecycleModifier: ViewModifier {
    let model: BrowserPeekModel
    let dismiss: () -> Void
    let promote: () -> Void
    let installsKeyboardMonitor: Bool

    init(
        model: BrowserPeekModel,
        dismiss: @escaping () -> Void,
        promote: @escaping () -> Void,
        installsKeyboardMonitor: Bool = true
    ) {
        self.model = model
        self.dismiss = dismiss
        self.promote = promote
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
            .onKeyPress(.return) {
                promote()
                return .handled
            }
            .background {
                BrowserPeekKeyboardMonitor(
                    dismiss: dismiss,
                    promote: promote,
                    installsMonitor: installsKeyboardMonitor
                )
                .frame(width: 0, height: 0)
            }
    }
}

#Preview {
    Text("Peek input")
        .modifier(
            BrowserPeekInputLifecycleModifier(
                model: BrowserPeekPreviewFixture.makeModel(),
                dismiss: {},
                promote: {},
                installsKeyboardMonitor: false
            )
        )
}
