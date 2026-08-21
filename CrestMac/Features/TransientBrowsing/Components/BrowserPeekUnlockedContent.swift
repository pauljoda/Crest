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
        BrowserTransientSurface(
            state: presentationState,
            pageStatus: pageStatus,
            spaces: model.availableSpaces,
            selectedSpaceID: model.request.spaceID,
            vocabulary: BrowserPeekVocabulary.overlay,
            actions: actions,
            // A pointer overlay is dismissed with a click or a key, never
            // carried away, so nothing ever moves this.
            dismissalOffset: .constant(0)
        ) {
            webContent
        }
        .modifier(taskLifecycle)
        .modifier(
            BrowserPeekInputLifecycleModifier(
                model: model,
                dismiss: dismiss,
                installsKeyboardMonitor: installsKeyboardMonitor
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Peek from \(model.request.sourceTitle)")
    }

    /// The window's own web content, handed to the shared card. The page and
    /// the pool that owns it are macOS types, so they never cross into the
    /// shared surface.
    @ViewBuilder
    private var webContent: some View {
        if let page = model.page, let pages = model.pages {
            BrowserWebContentView(
                page: page,
                browser: model.browser,
                pages: pages
            )
        }
    }

    private var presentationState: BrowserTransientPresentationState {
        BrowserTransientPresentationState(
            arrangement: .pointer,
            reservedLeadingWidth: reservedLeadingWidth,
            layoutDirection: layoutDirection,
            isCardVisible: isCardVisible,
            isCardExpanded: isCardExpanded,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            sourcePresentation: .resolved(model.request.sourcePresentation)
        )
    }

    private var pageStatus: BrowserTransientPageStatus {
        BrowserTransientPageStatus(
            hasPage: model.page != nil && model.pages != nil,
            wasReleasedForMemoryPressure:
                model.pageLease?.wasReleasedForMemoryPressure == true,
            initialLoadingCoverLabel: showsInitialLoadingSurface
                ? BrowserPeekVocabulary.initialLoadingCoverLabel
                : nil
        )
    }

    private var actions: BrowserTransientCardActions {
        BrowserTransientCardActions(
            dismiss: dismiss,
            promote: promote,
            restore: model.restorePage
        )
    }

    /// Whether the card still has to cover a page that has been handed a URL
    /// but has painted nothing. A page that failed has its own thing to say.
    private var showsInitialLoadingSurface: Bool {
        guard let page = model.page else { return false }
        return !isInitialWebContentRevealed
            && page.navigationFailure == nil
            && page.webContentFailureMessage == nil
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
