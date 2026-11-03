import SwiftUI

/// The manual setup the core holds on iPhone and iPad, which stays a setup
/// until the host's final action applies it.
struct MobileSpaceSetupWizard: View {
    let setup: BrowserManualSetupModel
    @Binding var selectedSpaceID: UUID?
    var errorMessage: String?
    var opensGettingStarted = true
    let back: () -> Void
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .appearance

    /// A page of the wizard: what it shows, and what Back and Continue do
    /// from it.
    private struct Step: Hashable, Sendable {
        // MARK: - Types

        /// The wizard switches on the kind to choose the page's concrete view.
        enum Kinds: Sendable {
            case appearance
            case ready
        }

        // MARK: - Static Variables

        static let appearance: Step = Step(
            kind: .appearance, position: 0, title: "01 — Appearance", continueTitle: "Continue",
            back: { wizard in wizard.back() },
            next: { wizard in wizard.step = .ready })
        static let ready: Step = Step(
            kind: .ready, position: 1, title: "02 — Your Spaces", continueTitle: "Open Crest",
            back: { wizard in wizard.step = .appearance },
            next: { wizard in wizard.finish() })

        // MARK: - Variables

        let kind: Kinds
        /// The page's place in setup, counted from zero.
        let position: Int
        let title: LocalizedStringResource
        let continueTitle: LocalizedStringResource
        let back: @MainActor @Sendable (MobileSpaceSetupWizard) -> Void
        let next: @MainActor @Sendable (MobileSpaceSetupWizard) -> Void

        // MARK: - Actions - Identity

        static func == (lhs: Step, rhs: Step) -> Bool {
            lhs.position == rhs.position
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(position)
        }
    }

    private var draft: SetupDraftSpace? {
        setup.space(selectedSpaceID)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            VStack(spacing: 0) {
                progress
                if let draft {
                    let branding = setup.brandingBinding(for: draft.spaceID)
                    let symbol = setup.symbolBinding(for: draft.spaceID)
                    if step == .appearance {
                        BrowserMobileSpaceAppearanceWorkspace(
                            branding: branding, symbol: symbol,
                            name: setup.nameBinding(for: draft.spaceID),
                            spacePicker: spacePicker(for: draft.spaceID)
                        )
                        .id(draft.spaceID)
                    } else {
                        ScrollView {
                            page(draft: draft, branding: branding, symbol: symbol, compact: !wide)
                                .padding(24)
                                .frame(maxWidth: 600)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    ContentUnavailableView("Create your first Space", systemImage: "square.grid.2x2")
                    Button("Add Space", action: addSpace).buttonStyle(.borderedProminent)
                }
                footer
            }
            .foregroundStyle(CrestBrandTheme.textDisplay)
            .font(CrestTypography.sans(14))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: step)
            .background {
                Rectangle().fill(CrestBrandTheme.surface)
                if let draft {
                    RadialGradient(
                        colors: [
                            draft.customization.branding.secondaryColor.color.opacity(0.12),
                            .clear,
                        ],
                        center: .init(x: 0.22, y: 0.48), startRadius: 0, endRadius: 500)
                }
            }
        }
        .onAppear { setup.repairSelection($selectedSpaceID) }
        .onChange(of: setup.spaces.map(\.spaceID)) { _, _ in setup.repairSelection($selectedSpaceID) }
    }

    private var progress: some View {
        HStack(spacing: 10) {
            CrestStartPageMark().frame(width: 24, height: 24)
            Text("Crest Setup").font(CrestTypography.sans(13, weight: .bold))
            Spacer()
            Text(step.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(0..<2) { index in
                    Capsule().fill(
                        index <= step.position ? CrestBrandPalette.butter : Color.secondary.opacity(0.15)
                    )
                    .frame(width: index == step.position ? 22 : 6, height: 6)
                }
            }
            .padding(.leading, 10)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(CrestBrandTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(CrestBrandTheme.line).frame(height: 1) }
    }

    @ViewBuilder private func page(
        draft: SetupDraftSpace, branding: Binding<SpaceBranding>,
        symbol: Binding<String>, compact: Bool
    ) -> some View {
        switch step.kind {
        case .appearance:
            BrowserSpaceBrandingEditor(branding: branding, symbol: symbol, compact: compact, showsPreview: false)
                .id(draft.spaceID)
        case .ready:
            spacesReview
        }
    }

    /// The Spaces setup made, to review or add to before opening Crest.
    private var spacesReview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your Spaces are ready").font(CrestTypography.display(36))
            Text("Review your Spaces or add another before opening Crest.")
                .foregroundStyle(.secondary)
            ForEach(setup.spaces, id: \.spaceID) { space in
                Button {
                    selectedSpaceID = space.spaceID
                    step = .appearance
                } label: {
                    HStack(spacing: 16) {
                        BrowserSpaceEditorIdentityPreview(
                            branding: space.customization.branding,
                            symbol: space.customization.symbol, size: 44)
                        Text(space.shownName).font(.headline)
                        Spacer()
                        Text("Edit").foregroundStyle(.secondary)
                        Image(systemName: "chevron.forward").foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .browserOnboardingPanel()
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if space.isNew {
                        Button("Remove Space", systemImage: "trash", role: .destructive) {
                            setup.removeSpace(space.spaceID)
                        }
                        .crestMenuActionLabelStyle()
                    }
                }
            }
            Button("Add another Space", systemImage: "plus", action: addSpace)
                .buttonStyle(.crestSecondary)
                .controlSize(.large)
            if opensGettingStarted {
                Text("Getting Started opens next with practice for tabs and folders.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let message = errorMessage ?? setup.errorMessage {
                Text(message).foregroundStyle(CrestColor.danger).font(.callout)
            }
            HStack {
                Button {
                    step.back(self)
                } label: {
                    Label("Back", systemImage: "arrow.left")
                }
                .buttonStyle(.crestSecondary)
                Spacer()
                Button {
                    step.next(self)
                } label: {
                    HStack(spacing: 20) {
                        Text(step.continueTitle)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
                .keyboardShortcut(.defaultAction)
                .disabled(draft == nil)
                .accessibilityIdentifier("space-setup-continue")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(CrestBrandTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(CrestBrandTheme.line).frame(height: 1) }
    }

    private func addSpace() {
        if let added = setup.addSpace() { selectedSpaceID = added }
        step = .appearance
    }

    private func spacePicker(for spaceID: UUID) -> BrowserSpaceCustomizationPicker {
        BrowserSpaceCustomizationPicker(
            spaces: setup.previewSpaces,
            selectedSpaceID: spaceID,
            selectSpace: {
                selectedSpaceID = $0
                setup.errorMessage = nil
                step = .appearance
            },
            moveSpace: { setup.moveSpace($0, to: $1) }, addSpace: addSpace)
    }
}
