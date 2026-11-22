import SwiftUI

/// Setup's sheet of paper: the welcome, filling the window, then each step in
/// turn on a third of it, with the steps as colored chips along the top, the
/// one open now named, and along the bottom Back to the page before and the
/// way on: to the next step, or into Crest.
struct BrowserSetupStepsPanel: View {
    // MARK: - Variables

    let flow: BrowserOnboardingFlow
    /// How wide the steps lie once the welcome gives way to them.
    let stepsWidth: CGFloat
    let welcome: BrowserOnboardingWelcomeAction
    /// Whether setup was opened for one step, so the list offers Cancel.
    let closes: Bool
    @Binding var path: [BrowserSetupDestination]
    @Binding var shownSpaceID: UUID?
    let close: () -> Void
    let startBrowsing: () -> Void
    let openCrest: () -> Void
    let setUpWithoutCloud: () -> Void

    /// Whether the last move went back, which the stack slides toward the
    /// trailing edge.
    @State private var isGoingBack = false

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack(alignment: .topLeading) {
            if path.isEmpty {
                landing
                    .transition(.opacity)
            } else {
                steps
                    .frame(width: stepsWidth)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .disabled(flow.isCompletingSetup || flow.isCommittingImport)
    }

    /// The welcome: the steps ahead, a greeting, and the way in.
    private var landing: some View {
        BrowserSetupLanding(steps: walk.steps, welcome: welcome, open: welcomeOpener) {
            if closes {
                Button("Cancel", action: close)
                    .buttonStyle(.crestSecondary)
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.cancel)
            } else if welcome.opensCrest {
                Button("Start Browsing", action: openCrest)
                    .buttonStyle(.crestSecondary)
                    .help("Start Crest with your Spaces from iCloud, without setting it up")
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.openCrest)
            }
        } forward: {
            HStack(spacing: CrestSpacing.medium) {
                if isCheckingCloud {
                    ProgressView().controlSize(.small)
                }
                forward
                    .buttonStyle(.crestPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The step open now, its page, and the way on.
    private var steps: some View {
        VStack(spacing: 0) {
            header
            BrowserSetupPageStack(path: path, isGoingBack: isGoingBack) { destination in
                page(destination)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
    }

    /// How far the walkthrough has come, as the welcome's chips.
    private var header: some View {
        BrowserSetupStepChips(steps: walk.steps, current: path.first?.step, size: .compact, open: openStep)
            .padding(.horizontal, BrowserSetupStepsPanelMetrics.headerInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: BrowserSetupStepsPanelMetrics.headerHeight)
            .padding(.top, BrowserSetupStepsPanelMetrics.headerTop)
    }

    @ViewBuilder
    private func page(_ destination: BrowserSetupDestination?) -> some View {
        if let destination {
            switch destination.kind {
            case .bring:
                BrowserSetupBringPage(flow: flow, open: { go(to: .source) })
            case .source:
                BrowserSetupSourcePage(flow: flow, shownSpaceID: $shownSpaceID)
            case .yourSpace:
                if let spaceID = firstSpaceID {
                    BrowserSetupSpacePage(
                        editor: BrowserSetupSpaceEditor(flow: flow, spaceID: spaceID), spaceID: spaceID,
                        title: "Your Space")
                }
            case .spaces:
                BrowserSetupSpacesPage(
                    preview: flow.setupPreview, setup: flow.manualSetup, incomingSpaceIDs: flow.incomingSpaceIDs,
                    open: { spaceID in
                        shownSpaceID = spaceID
                        go(to: .space(spaceID))
                    })
            case .space:
                if let spaceID = destination.spaceID {
                    BrowserSetupSpacePage(
                        editor: BrowserSetupSpaceEditor(flow: flow, spaceID: spaceID), spaceID: spaceID)
                }
            case .home:
                BrowserSetupHomePage(core: flow.manualSetup.core)
            }
        }
    }

    /// Back on the leading side, to the page before; the way on, on the
    /// trailing side.
    private var footer: some View {
        HStack(spacing: CrestSpacing.medium) {
            Button("Back", systemImage: "chevron.left", action: goBack)
                .buttonStyle(.crestSecondary)
                .accessibilityIdentifier(BrowserSetupAccessibilityID.back)
            if flow.isCommittingImport || flow.isCompletingSetup {
                ProgressView().controlSize(.small)
            }
            Spacer()
            forward
                .buttonStyle(.crestPrimary)
                .keyboardShortcut(.defaultAction)
        }
        .padding(BrowserSetupStepsPanelMetrics.footerInset)
    }

    /// The way on: into the walkthrough, on to the next step, back up from
    /// a page deeper in a step, or into Crest.
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
                    .disabled(flow.isReading)
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.startBrowsing)
            }
        } else {
            Button("Continue") {
                if welcome.waitsOnCloud { setUpWithoutCloud() }
                go(to: .bring)
            }
            .disabled(isCheckingCloud)
            .accessibilityIdentifier(BrowserSetupAccessibilityID.continue)
        }
    }

    /// Whether the welcome waits on iCloud and offers no way past it yet.
    private var isCheckingCloud: Bool { moves.isCheckingCloud(path) }

    /// How the steps move, as on every platform.
    private var moves: BrowserSetupStepMoves {
        BrowserSetupStepMoves(
            walk: walk, welcome: welcome, firstSpaceID: firstSpaceID, setUpWithoutCloud: setUpWithoutCloud)
    }

    /// The order of the steps: Bring Tabs, then the Spaces another browser
    /// brings, or else the person's first Space and then any more.
    private var walk: BrowserSetupWalk {
        BrowserSetupWalk(imports: flow.hasIncomingSpaces)
    }

    /// The Space Your Space makes: the first one the setup holds.
    private var firstSpaceID: UUID? {
        flow.manualSetup.spaces.first?.spaceID
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

enum BrowserSetupStepsPanelMetrics {
    static let headerHeight: CGFloat = 40
    /// The chips sit below the window's buttons, which lie over the sheet.
    static let headerTop: CGFloat = 40
    static let headerInset: CGFloat = 30
    static let footerInset = EdgeInsets(top: 12, leading: 30, bottom: 26, trailing: 30)
}
