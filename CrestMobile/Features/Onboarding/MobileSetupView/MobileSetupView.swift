import SwiftUI

/// Setup on iPhone and iPad as on a Mac: the steps, each opening its page in
/// a navigation stack, with Crest itself over a live copy of what setup
/// builds, at its real size: beside the steps on an iPad, above them on an
/// iPhone. When setup finishes, the copy grows to fill the screen before
/// Crest shows.
struct MobileSetupView: View {
    // MARK: - Variables

    let browser: BrowserStore
    let setup: BrowserManualSetupModel
    let welcome: BrowserOnboardingWelcomeAction
    /// The page setup opens on: the list of steps, or the step the person
    /// came for.
    let firstPath: [BrowserSetupDestination]
    /// Whether setup was opened for one step, so it offers Cancel.
    let closes: Bool
    let errorMessage: String?
    /// Whether setup is finishing, which holds every action.
    let isFinishing: Bool
    /// Whether setup finished and the copy grows to fill the screen.
    var isTakingOver = false
    let setUpWithoutCloud: () -> Void
    let startBrowsing: () -> Void
    let openCrest: () -> Void
    let close: () -> Void

    @State private var path: [BrowserSetupDestination] = []
    @State private var shownSpaceID: UUID?
    @State private var draftPreview = BrowserSetupDraftPreview()
    @State private var live = MobileSetupLiveSession()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var preview: BrowserSessionPreview? {
        draftPreview.preview(of: setup, in: browser)
    }

    /// The session setup would leave, as the copy opens over it.
    private var setupSession: BrowserSetupSession? {
        preview.map { BrowserSetupSession(seed: $0.seed(wearing: nil), images: $0.images) }
    }

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            if horizontalSizeClass == .regular, geometry.size.width >= MobileSetupViewMetrics.besideWidth {
                HStack(spacing: 0) {
                    steps
                        .frame(width: isTakingOver ? 0 : MobileSetupViewMetrics.panelWidth(in: geometry.size.width))
                        .clipped()
                        .opacity(isTakingOver ? 0 : 1)
                    if !isTakingOver { Divider() }
                    besideCopy
                }
            } else {
                VStack(spacing: 0) {
                    copyAbove
                        .frame(
                            height: isTakingOver
                                ? geometry.size.height : geometry.size.height * MobileSetupViewMetrics.previewShare)
                    if !isTakingOver {
                        Divider()
                        steps
                    }
                }
            }
        }
        .onAppear {
            if path.isEmpty { path = firstPath }
        }
        .onChange(of: setupSession, initial: true) { _, session in
            guard let session else { return }
            live.show(session.seed, images: session.images, spaceID: shownSpaceID)
        }
        .onChange(of: shownSpaceID) { _, spaceID in live.show(spaceID) }
        .onDisappear(perform: live.close)
    }

    /// The copy beside the steps at its real size, filling the screen once
    /// setup finishes.
    private var besideCopy: some View {
        MobileSetupLiveWindow(session: live, cornerRadius: isTakingOver ? 0 : MobileSetupLiveWindowMetrics.cornerRadius)
            .padding(isTakingOver ? 0 : MobileSetupViewMetrics.previewInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CrestColor.chromeSurface)
    }

    /// The copy above the steps at the room's real size, so it reads and
    /// takes touches as Crest does, growing to fill the screen when setup
    /// finishes.
    private var copyAbove: some View {
        MobileSetupLiveWindow(session: live, cornerRadius: isTakingOver ? 0 : MobileSetupLiveWindowMetrics.cornerRadius)
            .padding(isTakingOver ? 0 : MobileSetupViewMetrics.previewInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CrestColor.chromeSurface)
    }

    private var steps: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                BrowserSetupRootPage(welcome: welcome)
                    .navigationTitle(Text("Welcome"))
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: BrowserSetupDestination.self) { destination in
                        page(destination)
                            .navigationTitle(title(of: destination))
                            .toolbarTitleDisplayMode(.inline)
                            .environment(\.browserSetupShowsHeadings, false)
                    }
            }
            footer
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(.primary)
        .environment(\.crestControlAccent, .primary)
    }

    @ViewBuilder
    private func page(_ destination: BrowserSetupDestination) -> some View {
        switch destination.kind {
        case .bring, .source:
            MobileSetupBringPage()
        case .yourSpace:
            if let spaceID = setup.spaces.first?.spaceID {
                BrowserSetupSpacePage(
                    editor: BrowserSetupSpaceEditor(setup: setup, spaceID: spaceID), spaceID: spaceID,
                    title: "Your Space"
                )
                .onAppear { shownSpaceID = spaceID }
            }
        case .spaces:
            BrowserSetupSpacesPage(preview: preview, setup: setup) { spaceID in
                shownSpaceID = spaceID
                path.append(.space(spaceID))
            }
        case .space:
            if let spaceID = destination.spaceID {
                BrowserSetupSpacePage(
                    editor: BrowserSetupSpaceEditor(setup: setup, spaceID: spaceID), spaceID: spaceID
                )
                .onAppear { shownSpaceID = spaceID }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: CrestSpacing.small) {
            if let message = errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(CrestColor.danger)
            }
            HStack(spacing: CrestSpacing.medium) {
                if path.isEmpty, closes {
                    Button("Cancel", action: close)
                        .buttonStyle(.crestSecondary)
                        .accessibilityIdentifier("setup-cancel")
                } else if path.isEmpty, welcome.opensCrest {
                    Button("Start Browsing", action: openCrest)
                        .buttonStyle(.crestSecondary)
                        .accessibilityIdentifier("setup-open-crest")
                }
                if isFinishing || isCheckingCloud {
                    ProgressView()
                }
                Spacer()
                primaryButton
            }
        }
        .padding(.horizontal, CrestSpacing.large)
        .padding(.vertical, CrestSpacing.medium)
        .background(.bar)
        .disabled(isFinishing)
    }

    /// The way on: into the walkthrough, on to the next step, back up from
    /// a page deeper in a step, or into Crest. The navigation bar's back
    /// button leads back.
    @ViewBuilder
    private var primaryButton: some View {
        Group {
            if let current = path.last {
                if current.stepPage != nil {
                    Button("Done") { withAnimation(motion) { _ = path.popLast() } }
                        .accessibilityIdentifier("setup-done")
                } else if let next = walk.page(after: current) {
                    Button("Continue") { withAnimation(motion) { path.append(next) } }
                        .accessibilityIdentifier("setup-continue")
                } else {
                    Button("Start Browsing", action: startBrowsing)
                        .accessibilityIdentifier("setup-start-browsing")
                }
            } else {
                Button("Continue") {
                    if welcome.waitsOnCloud { setUpWithoutCloud() }
                    withAnimation(motion) { path = [.bring] }
                }
                .disabled(isCheckingCloud)
                .accessibilityIdentifier("setup-continue")
            }
        }
        .buttonStyle(.crestPrimary)
    }

    /// Whether the welcome waits on iCloud and offers no way past it yet.
    private var isCheckingCloud: Bool {
        path.isEmpty && welcome.waitsOnCloud && !welcome.offersSetupWithoutCloud
    }

    /// The order of the steps: Bring Tabs, which on this device points to a
    /// Mac, then the person's first Space and any more.
    private var walk: BrowserSetupWalk {
        BrowserSetupWalk(imports: false)
    }

    // MARK: - Actions - Reading

    /// The name a page shows in the navigation bar: its step, or the Space it
    /// edits.
    private func title(of destination: BrowserSetupDestination) -> Text {
        guard let spaceID = destination.spaceID else { return Text(destination.title) }
        let name =
            setup.space(spaceID)?.customization.name ?? preview?.space(id: spaceID)?.settings.name ?? ""
        return name.isEmpty ? Text("Untitled Space") : Text(verbatim: name)
    }

    private var motion: Animation? {
        CrestMotion.onboardingStep.unlessReducingMotion(reduceMotion)
    }
}

enum MobileSetupViewMetrics {
    /// The narrowest regular width that sets the preview beside the steps.
    static let besideWidth: CGFloat = 700
    /// The steps take about a third of the width beside the preview, within these widths.
    static let panelWidths: ClosedRange<CGFloat> = 340...420
    /// The share of an iPhone's height the preview takes above the steps.
    static let previewShare: CGFloat = 0.36
    static let previewInset: CGFloat = 16

    static func panelWidth(in width: CGFloat) -> CGFloat {
        min(max(width / 3, panelWidths.lowerBound), panelWidths.upperBound)
    }
}
