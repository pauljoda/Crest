import SwiftUI

struct MobileBrowserTransientUnlockedContent: View {
    let model: MobileBrowserTransientOverlayModel
    let presentationPhase: BrowserPeekPresentationPhase

    init(model: MobileBrowserTransientOverlayModel, presentationPhase: BrowserPeekPresentationPhase) {
        self.model = model
        self.presentationPhase = presentationPhase
        _retainedMotionState = State(initialValue: model.motionState)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCardVisible = false
    @State private var isCardExpanded = false
    @State private var retainedMotionState: BrowserPeekMotionState?

    var body: some View {
        BrowserTransientSurface(
            state: presentationState,
            pageStatus: pageStatus,
            spaces: model.availableSpaces,
            selectedSpaceID: model.request.spaceID,
            vocabulary: model.request.overlayVocabulary,
            actions: actions
        ) {
            webContent
        }
        .task(id: presentationPhase) {
            await updatePresentation()
        }
        .onChange(of: model.motionState) { _, state in
            if let state { retainedMotionState = state }
        }
        .task(id: model.activityRevision) {
            await model.autoArchiveAfterInactivity()
        }
        .onChange(of: model.completedNavigationCount) { oldCount, newCount in
            guard presentationPhase == .committed,
                let newCount,
                newCount > 0,
                newCount != oldCount
            else { return }
            model.recordCompletedNavigation(
                newCount,
                during: presentationPhase
            )
        }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .allowsHitTesting(presentationPhase == .committed)
        .accessibilityHidden(presentationPhase == .staged)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.request.accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(model.request.accessibilityIdentifier)
    }

    /// This shell's own web view, handed to the shared card. The page is a
    /// mobile type, so it never crosses into the shared surface.
    @ViewBuilder
    private var webContent: some View {
        if let page = model.page {
            MobileBrowserWebView(page: page)
                .id(page.tabID)
        }
    }

    private var presentationState: BrowserTransientPresentationState {
        BrowserTransientPresentationState(
            arrangement: .current,
            isCardVisible: !model.request.isQuickWindow || isCardVisible,
            isCardExpanded: model.request.isQuickWindow ? isCardExpanded : presentationPhase == .committed,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            presentationPhase: presentationPhase,
            sourcePresentation: model.request.sourcePresentation,
            motionState: model.motionState ?? retainedMotionState
        )
    }

    private var pageStatus: BrowserTransientPageStatus {
        BrowserTransientPageStatus(
            hasPage: model.page != nil,
            wasReleasedForMemoryPressure:
                model.pageLease?.wasReleasedForMemoryPressure == true,
            initialLoadingCoverLabel: showsInitialLoadingSurface
                ? model.request.overlayVocabulary.loadingTitle : nil
        )
    }

    private var showsInitialLoadingSurface: Bool {
        guard let page = model.page, !model.request.isQuickWindow else { return false }
        return page.committedNavigationCount == 0 && page.navigationFailure == nil
    }

    private var actions: BrowserTransientCardActions {
        BrowserTransientCardActions(
            dismiss: dismiss,
            promote: promote,
            restore: model.restorePage
        )
    }

    private var accessibilityValue: String {
        presentationPhase == .committed
            ? "Preview open"
            : "Preview preparing"
    }

    private func updatePresentation() async {
        guard model.preparePage(isActive: scenePhase == .active) else { return }
        if let completedNavigationCount = model.completedNavigationCount {
            model.recordCompletedNavigation(
                completedNavigationCount,
                during: presentationPhase
            )
        }
        guard presentationPhase == .committed else { return }
        // All Peek inputs use the shared motion state; only Quick Window has
        // its independent scene entrance.
        guard model.request.isQuickWindow else { return }
        guard !reduceMotion else {
            isCardVisible = true
            isCardExpanded = true
            return
        }
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.quickPeekEntrance,
                reduceMotion: reduceMotion
            )
        ) {
            isCardVisible = true
            isCardExpanded = true
        }
    }

    private func dismiss() {
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.peekDismissal,
                reduceMotion: reduceMotion
            )
        ) {
            model.dismiss()
        }
    }

    private func promote(_ assignment: BrowserSpaceRuntimeAssignment) {
        _ = model.promote(to: assignment)
    }
}
