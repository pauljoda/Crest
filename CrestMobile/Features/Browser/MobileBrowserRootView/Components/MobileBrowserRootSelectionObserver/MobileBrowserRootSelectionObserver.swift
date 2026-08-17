import SwiftUI

struct MobileBrowserRootSelectionObserver: ViewModifier {
    let selection: MobileBrowserRootSelectionSnapshot
    let lock: MobileBrowserRootLockSnapshot
    let selectionChanged:
        (
            MobileBrowserRootSelectionSnapshot,
            MobileBrowserRootSelectionSnapshot
        ) -> Void
    let lockChanged:
        (
            MobileBrowserRootLockSnapshot,
            MobileBrowserRootLockSnapshot
        ) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: selection) { previous, current in
                selectionChanged(previous, current)
            }
            .onChange(of: lock, initial: true) { previous, current in
                lockChanged(previous, current)
            }
    }
}
