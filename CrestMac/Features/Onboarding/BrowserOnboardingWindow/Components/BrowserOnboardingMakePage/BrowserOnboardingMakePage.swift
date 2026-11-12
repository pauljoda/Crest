import SwiftUI

/// Making a Space yours: the Space as its sidebar beside a page, its name
/// edited there, and one sheet of what the look lets a first run change. The
/// full Forge waits in Settings.
struct BrowserOnboardingMakePage: View {
    let look: SetupLook
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    @Binding var name: String
    /// The Space as its icon draws it, for the page beside the sidebar.
    let identity: BrowserSpaceIdentity
    /// The Spaces being made, as chips, or nil for a page that makes one
    /// Space alone.
    var picker: BrowserOnboardingMakePicker? = nil
    /// Why the last edit was refused, when it was.
    var failure: BrowserOnboardingFailureText? = nil
    let back: BrowserOnboardingBackAction?
    let advanceTitle: Text
    let advance: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let inset = BrowserOnboardingStageMetrics.pageInset(for: geometry.size.width)
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 20) {
                    BrowserOnboardingHeadline("Make it yours")
                    Spacer()
                    if look.kind == .heraldic {
                        Button("Shuffle", systemImage: "shuffle") {
                            branding = BrowserCrestForge.shuffled(branding)
                        }
                        .buttonStyle(.crestSecondary)
                        .help("A new crest and sidebar for this Space")
                        .accessibilityIdentifier("space-forge-shuffle")
                    }
                    if let picker {
                        BrowserOnboardingMakeChips(picker: picker)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.top, 8)
                .padding(.bottom, 20)

                GeometryReader { body in
                    HStack(alignment: .top, spacing: BrowserOnboardingMakeMetrics.spacing) {
                        preview
                            .frame(width: previewWidth(in: body.size.width), height: body.size.height)
                        sheet
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, inset)
                .padding(.bottom, 8)

                BrowserOnboardingFooter(back: back) {
                    HStack(spacing: 22) {
                        if let failure {
                            BrowserOnboardingFailureMessage(message: failure)
                                .font(CrestTypography.sans(12, weight: .medium))
                                .foregroundStyle(CrestColor.danger)
                                .lineLimit(2)
                                .accessibilityIdentifier("onboarding-workflow-error")
                        }
                        BrowserOnboardingContinueButton(advanceTitle, action: advance)
                            .accessibilityIdentifier("space-setup-continue")
                    }
                }
            }
        }
    }

    /// The width the window takes of `available`: under half, and never
    /// narrower than its sidebar and a page beside it.
    private func previewWidth(in available: CGFloat) -> CGFloat {
        max(BrowserOnboardingMakeMetrics.minimumPreviewWidth, available * 0.44)
    }

    /// The Space as its window, its icon large on the page.
    private var preview: some View {
        BrowserOnboardingWindowPreview(
            branding: branding, symbol: symbol, name: name, editableName: $name, showsNameHint: true
        ) {
            BrowserSpaceIdentityIcon(identity: identity, size: BrowserOnboardingMakeMetrics.pageIconSize)
                .frame(
                    width: BrowserOnboardingMakeMetrics.pageIconSize, height: BrowserOnboardingMakeMetrics.pageIconSize)
        }
    }

    @ViewBuilder private var sheet: some View {
        switch look.kind {
        case .heraldic:
            BrowserOnboardingHeraldicSheet(branding: $branding, symbol: $symbol)
        case .modern:
            BrowserOnboardingModernSheet(branding: $branding, symbol: $symbol)
        case .simple:
            BrowserOnboardingSimpleSheet(branding: $branding, symbol: $symbol)
        }
    }
}

/// The Spaces a page makes, as chips with one to add.
struct BrowserOnboardingMakePicker {
    let spaces: [BrowserSpaceIdentity]
    let selectedID: UUID?
    let select: (UUID) -> Void
    let add: () -> Void
    /// Removes a Space the setup made, or nil for one it cannot remove.
    let remove: (UUID) -> (() -> Void)?
}

/// The Spaces being made as a rail of chips, with one to add. The rail
/// scrolls sideways where a setup has made more Spaces than fit the header.
private struct BrowserOnboardingMakeChips: View {
    let picker: BrowserOnboardingMakePicker

    var body: some View {
        CrestSpaceChipRail(
            spaces: CrestSpaceIdentity.list(picker.spaces),
            selection: Binding(
                get: { picker.selectedID },
                set: { if let id = $0 { picker.select(id) } }),
            add: CrestSpaceChipAddAction(
                title: "New Space", accessibilityIdentifier: "space-customization-add", perform: picker.add),
            commands: { space in picker.remove(space.id).map { [.remove($0)] } ?? [] }
        )
        .frame(maxWidth: BrowserOnboardingMakeMetrics.chipsWidth)
        .accessibilityLabel("Spaces")
    }
}

enum BrowserOnboardingMakeMetrics {
    /// The window never narrows past its sidebar and a page beside it.
    static let minimumPreviewWidth: CGFloat = 520
    /// Between the window and the sheet.
    static let spacing: CGFloat = 48
    /// The most of the header the Space chips take once they scroll.
    static let chipsWidth: CGFloat = 520
    static let pageIconSize: CGFloat = 180
    /// The artwork of a choice tile on the sheet.
    static let tileArtworkSize: CGFloat = 40
    static let swatchSize: CGFloat = 34
}
