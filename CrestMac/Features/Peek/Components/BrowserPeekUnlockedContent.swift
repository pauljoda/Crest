import SwiftUI

struct BrowserPeekUnlockedContent: View {
    let model: BrowserPeekModel
    let reservedLeadingWidth: CGFloat
    let layoutDirection: LayoutDirection
    let installsKeyboardMonitor: Bool

    init(
        model: BrowserPeekModel,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection,
        installsKeyboardMonitor: Bool = true
    ) {
        self.model = model
        self.reservedLeadingWidth = reservedLeadingWidth
        self.layoutDirection = layoutDirection
        self.installsKeyboardMonitor = installsKeyboardMonitor
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCardVisible = false
    @State private var isCardExpanded = false
    @State private var isInitialWebContentRevealed = false

    var body: some View {
        BrowserPeekSurface(
            model: model,
            state: surfaceState,
            dismiss: dismiss,
            promote: promote
        )
        .modifier(taskLifecycle)
        .modifier(
            BrowserPeekInputLifecycleModifier(
                model: model,
                dismiss: dismiss,
                promote: { promote(model.request.assignment) },
                installsKeyboardMonitor: installsKeyboardMonitor
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Peek from \(model.request.sourceTitle)")
    }

    private var surfaceState: BrowserPeekSurfaceState {
        BrowserPeekSurfaceState(
            reservedLeadingWidth: reservedLeadingWidth,
            layoutDirection: layoutDirection,
            isCardVisible: isCardVisible,
            isCardExpanded: isCardExpanded,
            isInitialWebContentRevealed: isInitialWebContentRevealed,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            sourcePresentation: .resolved(model.request.sourcePresentation)
        )
    }

    private var taskLifecycle: BrowserPeekTaskLifecycleModifier {
        BrowserPeekTaskLifecycleModifier(
            requestID: model.request.id,
            committedNavigationCount: model.page?.committedNavigationCount,
            completedNavigationCount: model.page?.completedNavigationCount,
            present: presentCard,
            reveal: revealInitialWebContentIfReady,
            recordCompletedNavigation: model.recordCompletedNavigation
        )
    }

    private func presentCard() async {
        guard model.preparePage(isActive: scenePhase == .active) else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        guard !reduceMotion else {
            isCardVisible = true
            isCardExpanded = true
            return
        }
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                BrowserPeekPresentationPolicy.entranceAnimation,
                reduceMotion: reduceMotion
            )
        ) {
            isCardVisible = true
            isCardExpanded = true
        }
    }

    private func revealInitialWebContentIfReady() async {
        guard let page = model.page,
            BrowserPeekPresentationPolicy.revealsInitialWebContent(
                committedNavigationCount: page.committedNavigationCount
            ),
            !isInitialWebContentRevealed
        else { return }
        try? await Task.sleep(for: .milliseconds(34))
        guard !Task.isCancelled else { return }
        isInitialWebContentRevealed = true
    }

    private func dismiss() {
        withAnimation(dismissAnimation) {
            model.dismiss()
        }
    }

    private func promote(_ assignment: BrowserSpaceRuntimeAssignment) {
        _ = model.promote(to: assignment)
    }

    private var dismissAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.peekDismissal,
            reduceMotion: reduceMotion
        )
    }
}
