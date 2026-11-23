import SwiftUI

/// Setup's steps on iPhone and iPad, as a Mac's sheet of paper holds them:
/// the welcome, then each step in turn with the steps as colored chips along
/// the top, the one open now named, and along the bottom Back to the page
/// before and the way on, to the next step or into Crest. Beside an iPad's
/// copy of Crest they lie on the paper it draws. Standing alone, on a phone
/// or an iPad held upright, they draw their own paper, and a Space's page
/// wears the Space's own look, with Preview to see the Space as Crest will
/// show it.
struct MobileSetupSteps: View {
    // MARK: - Variables

    let browser: BrowserStore
    let setup: BrowserManualSetupModel
    let welcome: BrowserOnboardingWelcomeAction
    /// Whether the steps fill the screen with no copy of Crest beside them.
    let standsAlone: Bool
    /// Whether setup was opened for one step, so the welcome offers Cancel.
    let closes: Bool
    let errorMessage: String?
    /// Whether setup is finishing, which holds every action.
    let isFinishing: Bool
    /// Whether setup is handing over to Crest, which slides steps standing
    /// alone away over it.
    let isTakingOver: Bool
    @Binding var path: [BrowserSetupDestination]
    @Binding var shownSpaceID: UUID?
    let setUpWithoutCloud: () -> Void
    let startBrowsing: () -> Void
    /// Brings Crest up behind setup, which the last step does once it has
    /// come on, so Crest is ready the moment setup hands over to it.
    let prepareCrest: () -> Void
    let openCrest: () -> Void
    let close: () -> Void

    @State private var draftPreview = BrowserSetupDraftPreview()
    /// Whether the last move went back, which the pages slide toward the
    /// trailing edge.
    @State private var isGoingBack = false
    /// The Space Preview shows, while it does.
    @State private var previewedSpace: BrowserSetupPreviewedSpace?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var preview: BrowserSessionPreview? {
        draftPreview.preview(of: setup, in: browser)
    }

    /// The order of the steps: Bring Tabs, which on this device points to a
    /// Mac, then the person's first Space and any more, then the choices that
    /// make Crest home.
    private var walk: BrowserSetupWalk {
        BrowserSetupWalk(imports: false)
    }

    /// Whether the welcome waits on iCloud and offers no way past it yet.
    private var isCheckingCloud: Bool { moves.isCheckingCloud(path) }

    /// How the steps move, as on every platform.
    private var moves: BrowserSetupStepMoves {
        BrowserSetupStepMoves(
            walk: walk, welcome: welcome, firstSpaceID: setup.spaces.first?.spaceID,
            setUpWithoutCloud: setUpWithoutCloud)
    }

    /// Whether the welcome's buttons run the width of a phone.
    private var fillsWidth: Bool {
        standsAlone && horizontalSizeClass == .compact
    }

    /// The Space whose page is open now, which steps standing alone wear.
    private var openSpace: SetupDraftSpace? {
        guard let current = path.last else { return nil }
        if current == .yourSpace { return setup.spaces.first }
        return current.spaceID.flatMap { setup.space($0) }
    }

    /// The look the steps wear: the open Space's, when they stand alone.
    private var wornLook: SpaceBranding? {
        standsAlone ? openSpace?.customization.branding : nil
    }

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack(alignment: .topLeading) {
            if path.isEmpty {
                landing
                    .transition(.opacity)
            } else {
                steps
                    .transition(.opacity)
            }
        }
        .browserSetupPaperContent(wearing: wornLook, over: colorScheme)
        .background {
            if standsAlone { background }
        }
        .tint(CrestBrandTheme.accent)
        .disabled(isFinishing)
        // Handing over, steps standing alone slide away down the screen.
        .visualEffect { [isTakingOver] content, geometry in
            content.offset(y: isTakingOver ? geometry.size.height : 0)
        }
        .sheet(item: $previewedSpace) { space in
            MobileSetupPreviewSheet(browser: browser, setup: setup, spaceID: space.id)
        }
    }

    /// Crest's paper, or, on a Space's page, the Space's own look.
    private var background: some View {
        ZStack {
            BrowserSetupPaper()
            if let wornLook {
                BrowserSpaceBannerBackground(branding: wornLook)
                    .transition(.opacity)
            }
        }
        .animation(CrestMotion.onboardingStep, value: openSpace?.spaceID)
        .ignoresSafeArea()
    }

    /// The welcome: the steps ahead, a greeting, and the way in, filling the
    /// screen as Crest's website opens on a Mac or an iPad, and stacked to
    /// the phone's width on a phone.
    @ViewBuilder
    private var landing: some View {
        if fillsWidth {
            MobileSetupPhoneLanding(
                steps: walk.steps, welcome: welcome, errorMessage: errorMessage, open: welcomeOpener
            ) {
                continueButton
            } other: {
                otherWayIn
            }
        } else {
            // At the largest text sizes the welcome can outgrow the screen,
            // so it scrolls rather than hide the way in.
            GeometryReader { geometry in
                ScrollView {
                    BrowserSetupLanding(steps: walk.steps, welcome: welcome, open: welcomeOpener) {
                        otherWayIn
                    } forward: {
                        continueButton
                    }
                    .overlay(alignment: .bottom) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(CrestColor.danger)
                                .multilineTextAlignment(.center)
                                .padding(MobileSetupStepsMetrics.footerInset)
                        }
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// The way in.
    private var continueButton: some View {
        Button {
            if welcome.waitsOnCloud { setUpWithoutCloud() }
            go(to: .bring)
        } label: {
            HStack(spacing: CrestSpacing.small) {
                if isCheckingCloud { ProgressView() }
                Text("Continue")
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.crestPrimary)
        .disabled(isCheckingCloud)
        .accessibilityIdentifier(BrowserSetupAccessibilityID.continue)
    }

    /// What the welcome offers beside the way in: Cancel when setup was
    /// opened for one step, or Crest as iCloud brought it.
    @ViewBuilder
    private var otherWayIn: some View {
        if closes {
            Button(action: close) {
                Text("Cancel").frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.crestSecondary)
            .accessibilityIdentifier(BrowserSetupAccessibilityID.cancel)
        } else if welcome.opensCrest {
            Button(action: openCrest) {
                Text("Start Browsing").frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.crestSecondary)
            .accessibilityIdentifier(BrowserSetupAccessibilityID.openCrest)
        }
    }

    /// The step open now, its page, and the way on. The page runs the
    /// whole height, to the bottom of the screen, and the chips and the
    /// buttons float over it: the page fades out under the chips and scrolls
    /// on under the buttons.
    private var steps: some View {
        GeometryReader { geometry in
            stepsLayers(bottomInset: geometry.safeAreaInsets.bottom)
        }
    }

    /// The page under the chips and the buttons, its end clear of the
    /// buttons and of `bottomInset`, the screen's own room at the bottom.
    private func stepsLayers(bottomInset: CGFloat) -> some View {
        ZStack {
            BrowserSetupPageStack(path: path, isGoingBack: isGoingBack) { destination in
                page(destination)
            }
            .contentMargins(.top, MobileSetupStepsMetrics.headerBand, for: .scrollContent)
            .contentMargins(.bottom, MobileSetupStepsMetrics.footerBand + bottomInset, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: MobileSetupStepsMetrics.headerBand)
                    Color.black
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            VStack(spacing: 0) {
                BrowserSetupStepChips(steps: walk.steps, current: path.first?.step, size: .compact, open: openStep)
                    .padding(.horizontal, MobileSetupStepsMetrics.headerInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: MobileSetupStepsMetrics.headerHeight)
                    .padding(.top, MobileSetupStepsMetrics.headerTop)
                Spacer(minLength: 0)
                footer
            }
        }
    }

    @ViewBuilder
    private func page(_ destination: BrowserSetupDestination?) -> some View {
        if let destination {
            switch destination.kind {
            case .bring, .source:
                MobileSetupBringPage()
            case .yourSpace:
                if let space = setup.spaces.first {
                    spacePage(space, title: "Your Space")
                }
            case .spaces:
                BrowserSetupSpacesPage(preview: preview, setup: setup) { spaceID in
                    shownSpaceID = spaceID
                    go(to: .space(spaceID))
                }
            case .space:
                if let space = setup.space(destination.spaceID) {
                    spacePage(space, title: nil)
                }
            case .home:
                BrowserSetupHomePage(core: setup.core)
                    .task {
                        // Once the page has come on, Crest comes up behind setup.
                        try? await Task.sleep(for: MobileSetupStepsMetrics.prepareDelay)
                        if !Task.isCancelled { prepareCrest() }
                    }
            }
        }
    }

    /// A Space's page, showing the Space large above its name, with Preview
    /// beside it, where no copy of Crest shows it.
    private func spacePage(_ space: SetupDraftSpace, title: LocalizedStringResource?) -> some View {
        BrowserSetupSpacePage(
            editor: BrowserSetupSpaceEditor(setup: setup, spaceID: space.spaceID), spaceID: space.spaceID,
            title: title, icon: standsAlone ? BrowserSpaceIdentity(draft: space) : nil,
            preview: standsAlone ? { previewedSpace = BrowserSetupPreviewedSpace(id: space.spaceID) } : nil
        )
        .onAppear { shownSpaceID = space.spaceID }
    }

    /// Back on the leading side, to the page before; the way on, on the
    /// trailing side; both floating over the page.
    private var footer: some View {
        VStack(spacing: CrestSpacing.small) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(CrestColor.danger)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: CrestSpacing.small) {
                // Frosted glass under the quiet pill, so the page scrolling
                // behind it doesn't show through its title.
                Button("Back", systemImage: "chevron.left", action: goBack)
                    .buttonStyle(.crestSecondary)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.back)
                Spacer(minLength: 0)
                if isFinishing { ProgressView() }
                forward
                    .buttonStyle(.crestPrimary)
            }
        }
        .padding(MobileSetupStepsMetrics.footerInset)
    }

    /// The way on: on to the next step, back up from a page deeper in a
    /// step, or into Crest.
    @ViewBuilder
    private var forward: some View {
        if let current = path.last {
            if current.stepPage != nil {
                Button("Done", action: goBack)
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.done)
            } else if let next = walk.page(after: current) {
                Button("Continue") { go(to: next, replacing: true) }
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.continue)
            } else {
                Button("Start Browsing", action: startBrowsing)
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.startBrowsing)
            }
        }
    }

    // MARK: - Mutators

    private func go(to destination: BrowserSetupDestination, replacing: Bool = false) {
        moves.go(
            to: destination, replacing: replacing, path: &path, isGoingBack: &isGoingBack, shownSpaceID: &shownSpaceID)
    }

    /// What the welcome's chips open, once nothing holds the way in.
    private var welcomeOpener: ((BrowserSetupStep) -> Void)? {
        guard !isCheckingCloud else { return nil }
        return { step in openStep(step) }
    }

    private func openStep(_ step: BrowserSetupStep) {
        moves.open(step, path: &path, isGoingBack: &isGoingBack, shownSpaceID: &shownSpaceID)
    }

    private func goBack() {
        moves.back(path: &path, isGoingBack: &isGoingBack)
    }
}

/// The Space Preview shows.
struct BrowserSetupPreviewedSpace: Identifiable {
    let id: UUID
}

enum MobileSetupStepsMetrics {
    static let headerHeight: CGFloat = 40
    static let headerTop: CGFloat = 12
    static let headerInset: CGFloat = 20
    /// The height of the chips' band, which the page starts below and fades
    /// out under.
    static let headerBand: CGFloat = 60
    static let footerInset = EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
    /// The room the page leaves after its end, so it scrolls clear of the
    /// buttons floating over it.
    static let footerBand: CGFloat = 76
    /// How long the last step waits, once it opens, to bring Crest up
    /// behind setup: past the slide that opens it.
    static let prepareDelay = Duration.milliseconds(800)
}
