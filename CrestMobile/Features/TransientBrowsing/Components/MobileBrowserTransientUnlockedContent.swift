import SwiftUI

struct MobileBrowserTransientUnlockedContent: View {
    let model: MobileBrowserTransientOverlayModel
    let presentationPhase: BrowserPeekPresentationPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCardVisible = false
    @State private var isCardExpanded = false

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
            isCardVisible: isCardVisible,
            isCardExpanded: isCardExpanded,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            presentationPhase: presentationPhase,
            sourcePresentation: model.request.sourcePresentation
        )
    }

    private var pageStatus: BrowserTransientPageStatus {
        BrowserTransientPageStatus(
            hasPage: model.page != nil,
            wasReleasedForMemoryPressure:
                model.pageLease?.wasReleasedForMemoryPressure == true
        )
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
        guard !reduceMotion else {
            isCardVisible = true
            isCardExpanded = true
            return
        }
        let animation =
            model.request.isQuickWindow
            ? CrestMotion.quickPeekEntrance
            : BrowserPeekPresentationPolicy.entranceAnimation
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                animation,
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
