import SwiftUI

/// Clears a lift when its drag session ends without landing on the sidebar.
///
/// A dropped row is cleared by the drop delegate that commits it. A drag that is
/// released elsewhere never reaches a delegate, and the lifted row stays hidden
/// because the system, not us, draws it while a session is live.
struct BrowserMobileReorderSessionModifier: ViewModifier {
    let state: BrowserSidebarReorderState

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                content.onDragSessionUpdated { session in
                    let phase: BrowserTabDragSessionLifecyclePhase =
                        switch session.phase {
                        case .ended: .ended
                        case .dataTransferCompleted: .dataTransferCompleted
                        default: .active
                        }
                    guard
                        BrowserTabDragSessionLifecyclePolicy.shouldEnd(for: phase)
                    else { return }
                    Task { @MainActor in state.cancel() }
                }
            } else {
                content
            }
        #else
            content
        #endif
    }
}
