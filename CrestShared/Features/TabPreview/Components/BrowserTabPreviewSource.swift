import SwiftUI

/// Tells the window's tab preview when the pointer or the keyboard rests on a
/// sidebar row, pinned tile or folder, and where it sits, so the window can
/// show its card beside the sidebar.
///
/// It reports only while the window draws cards, the preference is on, the
/// shell has a pointer and nothing is being dragged. The frame is measured
/// only while the row is rested on, so a scrolling list measures nothing for
/// the rows the pointer isn't on.
struct BrowserTabPreviewSource: ViewModifier {
    // MARK: - Variables

    let subject: BrowserTabPreviewSubject
    let context: BrowserSidebarListContext?

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
    @Environment(\.browserTabPreviewState) private var previewOverride
    @State private var isPointerOver = false
    /// The tab or folder as it was reported entered, until it is reported
    /// left.
    @State private var entered: BrowserTabPreviewKey?

    /// The preview this row reports to: its window's, or a folder card's own
    /// for the rows that card lists.
    private var preview: BrowserTabPreviewState? { previewOverride ?? sidebarInteraction?.tabPreview }

    /// Whether the pointer or the keyboard rests on the row while it may be
    /// previewed.
    private var isRested: Bool {
        guard let preview, preview.isHosted, preview.isSidebarShown, let context, context.capabilities.supportsHover,
            subject.isTurnedOn, !isDragging
        else { return false }
        return isPointerOver || isKeyboardFocused(in: context)
    }

    private var isDragging: Bool {
        guard let sidebarInteraction else { return false }
        return sidebarInteraction.tabDragState.item != nil || sidebarInteraction.sidebarReorderState.hasLiftInFlight
    }

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        content
            .onHover { isPointerOver = $0 }
            .background {
                if isRested {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .global)
                        Color.clear
                            .onAppear { report(frame) }
                            .onChange(of: frame) { _, frame in report(frame) }
                    }
                }
            }
            .onChange(of: isRested) { _, isRested in
                if !isRested { leave() }
            }
            .onDisappear { leave() }
    }

    /// Whether the arrow keys moved a selection's focus onto the row. A plain
    /// click focuses what it opens too, but the keys move the focus only
    /// through a selection a Command- or Shift-click began.
    private func isKeyboardFocused(in context: BrowserSidebarListContext) -> Bool {
        let selection = context.browser.tabMultiSelection
        return selection.isEngaged && selection.ownsKeyboardFocus && selection.focusedItem == subject.item
    }

    // MARK: - Actions - Reporting

    /// Tells the preview the row sits at `frame`. The frame can change once
    /// more after the pointer has left, as a sliding sidebar carries the row
    /// out from under it, and that change reports nothing.
    private func report(_ frame: CGRect) {
        guard isRested, let preview, let context, !frame.isEmpty else { return }
        var target = BrowserTabPreviewTarget(subject: subject, context: context, frame: frame)
        target.isRestedByPointer = !isKeyboardFocused(in: context)
        if entered == target.key {
            preview.move(target)
        } else {
            if let entered { preview.leave(entered) }
            entered = target.key
            preview.enter(target)
        }
    }

    private func leave() {
        guard let entered else { return }
        self.entered = nil
        preview?.leave(entered)
    }
}

extension EnvironmentValues {
    /// The preview the rows under this view report to in place of their
    /// window's, as a folder card's rows report to that card's own.
    @Entry var browserTabPreviewState: BrowserTabPreviewState? = nil
}

extension View {
    /// Reports this row or tile of `subject` to the window's tab preview.
    func browserTabPreviewSource(
        _ subject: BrowserTabPreviewSubject, in context: BrowserSidebarListContext?
    ) -> some View {
        modifier(BrowserTabPreviewSource(subject: subject, context: context))
    }

    /// Gives VoiceOver what a preview card adds about `tab`: its site, and
    /// when it was last viewed.
    func browserTabPreviewAccessibility(_ tab: TabStateModel) -> some View {
        self
            .accessibilityCustomContent(
                AccessibilityCustomContentKey("Site"),
                tab.address.map { Text(BrowserAddressPresentation($0.absoluteString).domain) }
            )
            .accessibilityCustomContent(
                AccessibilityCustomContentKey("Last viewed"),
                Text(tab.lastActivatedAt, format: .relative(presentation: .named, unitsStyle: .wide)))
    }
}
