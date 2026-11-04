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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isCardVisible = false
    @State private var isCardExpanded = false
    /// Whether the card is collapsing back into its link as it closes.
    @State private var isCollapsing = false
    @State private var retainedMotionState: BrowserPeekMotionState?
    @State private var windowPlacement: MobileBrowserTransientWindowPlacement?

    var body: some View {
        BrowserTransientSurface(
            state: presentationState,
            pageStatus: pageStatus,
            spaces: model.availableSpaceModels.map(\.identity),
            selectedSpaceID: model.request.spaceID,
            vocabulary: model.request.overlayVocabulary,
            actions: actions
        ) {
            webContent
        } linkMenuAnchor: { presentation in
            MobilePeekLinkMenuAnchor(presentation: presentation)
        }
        .background {
            MobileBrowserTransientWindowPlacement.Reader { windowPlacement = $0 }
                .ignoresSafeArea()
        }
        .task(id: presentationPhase) {
            await updatePresentation()
        }
        .onChange(of: model.motionState) { _, state in
            if let state { retainedMotionState = state }
        }
        .task(id: model.archiveTimer) {
            await model.autoArchiveAfterInactivity()
        }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
        }
        .onChange(of: model.isSelected) {
            model.setActive(scenePhase == .active)
        }
        .onKeyPress(.escape) {
            guard model.isSelected else { return .ignored }
            dismiss()
            return .handled
        }
        .allowsHitTesting(presentationPhase == .committed && !isCollapsing)
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
            arrangement: .fitting(
                horizontalSizeClass: horizontalSizeClass,
                verticalSizeClass: verticalSizeClass
            ),
            isCardVisible: followsMotion || isCardVisible,
            isCardExpanded: followsMotion ? presentationPhase == .committed : isCardExpanded,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            presentationPhase: presentationPhase,
            sourcePresentation: sourcePresentation,
            motionState: motionState
        )
    }

    private var motionState: BrowserPeekMotionState? {
        model.motionState ?? retainedMotionState
    }

    /// Whether the card follows the shared motion of a link the person tapped
    /// open, rather than growing out of a link they held.
    private var followsMotion: Bool {
        motionState != nil
    }

    /// The link the card grows from, measured against the overlay rather
    /// than the window the page measured it in.
    private var sourcePresentation: BrowserPeekSourcePresentation {
        .resolved(model.request.sourcePresentation.map { windowPlacement?.place($0) ?? $0 })
    }

    /// Whether closing the card shrinks it back into the link it grew from.
    private var collapsesIntoLink: Bool {
        !followsMotion && !model.request.isQuickWindow && model.request.sourcePresentation != nil
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
        return page.committedNavigationCount == 0 && page.live.failure == nil
    }

    private var actions: BrowserTransientCardActions {
        BrowserTransientCardActions(
            dismiss: dismiss,
            promote: promote,
            restore: model.restorePage,
            linkMenu: model.linkMenu
        )
    }

    private var accessibilityValue: String {
        presentationPhase == .committed
            ? "Preview open"
            : "Preview preparing"
    }

    /// A held link's Peek waits unseen behind the press, then grows out of
    /// the link once the press holds. A Peek tapped open follows the shared
    /// motion instead.
    private func updatePresentation() async {
        guard model.preparePage(isActive: scenePhase == .active) else { return }
        guard presentationPhase == .committed, !followsMotion else { return }
        let entrance = model.request.isQuickWindow ? CrestMotion.quickPeekEntrance : CrestMotion.peekEntrance
        withAnimation(entrance.unlessReducingMotion(reduceMotion)) {
            isCardVisible = true
            isCardExpanded = true
        }
    }

    private func dismiss() {
        guard !isCollapsing else { return }
        guard collapsesIntoLink, !reduceMotion else {
            withAnimation(
                CrestMotion.peekDismissal.unlessReducingMotion(reduceMotion)
            ) {
                model.dismiss()
            }
            return
        }
        isCollapsing = true
        withAnimation(CrestMotion.peekDismissal, completionCriteria: .logicallyComplete) {
            isCardVisible = false
            isCardExpanded = false
        } completion: {
            model.dismiss()
        }
    }

    private func promote(_ assignment: BrowserSpaceRuntimeAssignment) {
        _ = model.promote(to: assignment)
    }
}
