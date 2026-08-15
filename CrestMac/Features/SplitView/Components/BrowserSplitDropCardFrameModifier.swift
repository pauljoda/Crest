import SwiftUI

/// Reports where one presented card sits, in the global space a drag resolves
/// in, so a tab dropped on the content area lands in the slot the pointer is
/// actually over.
///
/// Both content-area layouts register through this: a card of a split, and the
/// single surface a window presenting one tab draws instead. Treating the lone
/// surface as a card of its own is what makes the first drop — the one that
/// creates a split — the same arithmetic as every later one, and it is also how
/// a tab dragged onto the very tab it already shows is recognised and refused.
///
/// A `nil` tab registers nothing: a locked Space shows its access gate rather
/// than a page, and there is no card there to join.
///
/// Registration is owner-stamped because the two layouts swap places mid-drag
/// and SwiftUI runs the departing view's `onDisappear` after the arriving one
/// has measured itself. Without the stamp the exit would clear the entry the
/// entrance just made, the cards would read as empty, and the drop target would
/// vanish under the pointer.
struct BrowserSplitDropCardFrameModifier: ViewModifier {
    let tabID: TabID?
    let state: BrowserSidebarReorderState

    @State private var identity = UUID()
    @State private var frame = CGRect.zero
    /// What this view last registered, so a changed tab — a new selection under
    /// an unchanged surface — takes its predecessor's entry with it.
    @State private var registeredTabID: TabID?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { newFrame in
                frame = newFrame
                register()
            }
            .onChange(of: tabID) { _, _ in
                register()
            }
            .onDisappear {
                unregister()
            }
    }

    private func register() {
        if let registeredTabID, registeredTabID != tabID {
            state.removeSplitCardFrame(for: registeredTabID, owner: identity)
            self.registeredTabID = nil
        }
        guard let tabID, !frame.isEmpty else { return }
        state.register(splitCardFrame: frame, for: tabID, owner: identity)
        registeredTabID = tabID
    }

    private func unregister() {
        guard let registeredTabID else { return }
        state.removeSplitCardFrame(for: registeredTabID, owner: identity)
        self.registeredTabID = nil
    }
}
