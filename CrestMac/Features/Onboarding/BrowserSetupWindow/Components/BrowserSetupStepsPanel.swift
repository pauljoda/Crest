import SwiftUI

/// The steps of setup on a panel over the room: the welcome, then each step
/// in turn, with how far the walkthrough has come along the top, and along
/// the bottom Back to the page before and the way on: into the steps, to the
/// next step, or into Crest.
struct BrowserSetupStepsPanel: View {
    // MARK: - Variables

    let flow: BrowserOnboardingFlow
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
        VStack(spacing: 0) {
            header
            BrowserSetupPageStack(path: path, isGoingBack: isGoingBack) { destination in
                page(destination)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .disabled(flow.isCompletingSetup || flow.isCommittingImport)
    }

    /// How far the walkthrough has come.
    private var header: some View {
        BrowserSetupProgressLine(steps: walk.steps, current: path.first?.step)
            .padding(.horizontal, BrowserSetupStepsPanelMetrics.headerInset)
            .frame(height: BrowserSetupStepsPanelMetrics.headerHeight)
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
            }
        } else {
            BrowserSetupRootPage(welcome: welcome)
        }
    }

    /// Back on the leading side, to the page before, or on a welcome that
    /// iCloud brought Spaces to, Start Browsing, which skips setup; the way
    /// on, on the trailing side.
    private var footer: some View {
        HStack(spacing: CrestSpacing.medium) {
            if path.isEmpty {
                if closes {
                    Button("Cancel", action: close)
                        .buttonStyle(.crestSecondary)
                        .accessibilityIdentifier("setup-cancel")
                } else if welcome.opensCrest {
                    Button("Start Browsing", action: openCrest)
                        .buttonStyle(.crestSecondary)
                        .help("Start Crest with your Spaces from iCloud, without setting it up")
                        .accessibilityIdentifier("setup-open-crest")
                }
            } else {
                Button("Back", systemImage: "chevron.left", action: goBack)
                    .buttonStyle(.crestSecondary)
                    .accessibilityIdentifier("setup-back")
            }
            if flow.isCommittingImport || flow.isCompletingSetup || isCheckingCloud {
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
                    .accessibilityIdentifier("setup-done")
            } else if let next = walk.page(after: current) {
                Button("Continue") { go(to: next, replacing: true) }
                    .accessibilityIdentifier("setup-continue")
            } else {
                Button("Start Browsing", action: startBrowsing)
                    .disabled(flow.isReading)
                    .accessibilityIdentifier("setup-start-browsing")
            }
        } else {
            Button("Continue") {
                if welcome.waitsOnCloud { setUpWithoutCloud() }
                go(to: .bring)
            }
            .disabled(isCheckingCloud)
            .accessibilityIdentifier("setup-continue")
        }
    }

    /// Whether the welcome waits on iCloud and offers no way past it yet.
    private var isCheckingCloud: Bool {
        path.isEmpty && welcome.waitsOnCloud && !welcome.offersSetupWithoutCloud
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
        isGoingBack = false
        if replacing { path = [destination] } else { path.append(destination) }
        if destination == .yourSpace, let firstSpaceID { shownSpaceID = firstSpaceID }
    }

    /// Up from a page deeper in a step, else to the step before, or from
    /// the first step to the welcome.
    private func goBack() {
        isGoingBack = true
        if path.count > 1 {
            path.removeLast()
        } else if let current = path.last, let before = walk.page(before: current) {
            path = [before]
        } else {
            path = []
        }
    }
}

enum BrowserSetupStepsPanelMetrics {
    static let headerHeight: CGFloat = 52
    static let headerInset: CGFloat = 30
    static let footerInset = EdgeInsets(top: 12, leading: 30, bottom: 26, trailing: 30)
}
