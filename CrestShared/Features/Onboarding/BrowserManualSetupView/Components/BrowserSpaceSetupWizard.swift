import SwiftUI

/// The plan stays a draft until the host's final action saves it.
struct BrowserSpaceSetupWizard: View {
    @Binding var plan: BrowserManualSetupPlan
    @Binding var selectedSpaceID: SpaceID?
    var errorMessage: String?
    var opensGettingStarted = true
    let back: () -> Void
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = BrowserManualSetupModel()
    @State private var step = Step.appearance

    private enum Step: Int { case appearance, ready }

    private var draft: BrowserManualSetupSpaceDraft? {
        model.selectedDraft(in: plan, selectedSpaceID: selectedSpaceID)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            VStack(spacing: 0) {
                progress
                if let draft {
                    let branding = model.brandingBinding(for: draft.id, plan: $plan)
                    let symbol = model.symbolBinding(for: draft.id, plan: $plan)
                    #if os(iOS)
                        if step == .appearance {
                            BrowserMobileSpaceAppearanceWorkspace(
                                branding: branding, symbol: symbol,
                                name: model.nameBinding(for: draft.id, plan: $plan),
                                spacePicker: spacePicker(for: draft.id), showsNameHint: true
                            )
                            .id(draft.id)
                        } else {
                            ScrollView {
                                page(draft: draft, branding: branding, symbol: symbol, compact: !wide)
                                    .padding(24)
                                    .frame(maxWidth: 600)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    #else
                        HStack(spacing: wide ? 26 : 0) {
                            if wide {
                                BrowserSpaceAppearanceHero(
                                    branding: branding.wrappedValue, symbol: symbol.wrappedValue,
                                    name: draft.customization.resolvedName,
                                    editableName: model.nameBinding(for: draft.id, plan: $plan), showsNameHint: true,
                                    spacePicker: spacePicker(for: draft.id)
                                )
                                .frame(width: min(280, geometry.size.width * 0.30), height: 440)
                            }
                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    if !wide {
                                        BrowserSpaceAppearanceHero(
                                            branding: branding.wrappedValue, symbol: symbol.wrappedValue,
                                            name: draft.customization.resolvedName, compact: true,
                                            editableName: model.nameBinding(for: draft.id, plan: $plan),
                                            showsNameHint: true,
                                            spacePicker: spacePicker(for: draft.id)
                                        )
                                        .frame(height: 192)
                                    }
                                    page(draft: draft, branding: branding, symbol: symbol, compact: !wide)
                                }
                                .padding(wide ? 24 : 20)
                                .id("space-setup-page-top")
                                .frame(
                                    maxWidth: 560, minHeight: wide ? min(520, geometry.size.height - 180) : nil,
                                    alignment: .topLeading
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .contentMargins(.trailing, 16, for: .scrollContent)
                            .id(step)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                        }
                        .frame(maxWidth: 1020, maxHeight: 580)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif
                } else {
                    ContentUnavailableView("Create your first Space", systemImage: "square.grid.2x2")
                    Button("Add Space", action: addSpace).buttonStyle(.borderedProminent)
                }
                footer
            }
            .foregroundStyle(BrowserOnboardingPalette.ink)
            .font(CrestTypography.sans(14))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: step)
            .background {
                Rectangle().fill(BrowserOnboardingPalette.parchment)
                if let draft {
                    RadialGradient(
                        colors: [draft.customization.branding.secondaryColor.color.opacity(0.12), .clear],
                        center: .init(x: 0.22, y: 0.48), startRadius: 0, endRadius: 500)
                }
            }
        }
        .scrollsSpaceAppearancePages(anchorID: "space-setup-page-top")
        .onAppear {
            if plan.spaces.isEmpty { addSpace() }
            model.repairSelection(plan: plan, selectedSpaceID: $selectedSpaceID)
        }
        .onChange(of: plan.spaces.map(\.id)) { _, _ in
            model.repairSelection(plan: plan, selectedSpaceID: $selectedSpaceID)
        }
    }

    private var chromeBackground: Color {
        #if os(iOS)
            BrowserOnboardingPalette.parchment
        #else
            BrowserOnboardingPalette.paper
        #endif
    }

    private var progress: some View {
        HStack(spacing: 10) {
            CrestStartPageMark().frame(width: 24, height: 24)
            Text("Crest Setup").font(CrestTypography.sans(13, weight: .bold))
            Spacer()
            Text(step == .appearance ? "01 — Appearance" : "02 — Your Spaces")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(0..<2) { index in
                    Capsule().fill(
                        index <= step.rawValue ? CrestBrandPalette.butter : Color.secondary.opacity(0.15)
                    )
                    .frame(width: index == step.rawValue ? 22 : 6, height: 6)
                }
            }
            .padding(.leading, 10)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(chromeBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(BrowserOnboardingPalette.line).frame(height: 1) }
    }

    @ViewBuilder private func page(
        draft: BrowserManualSetupSpaceDraft, branding: Binding<BrowserSpaceBranding>,
        symbol: Binding<String>, compact: Bool
    ) -> some View {
        switch step {
        case .appearance:
            BrowserSpaceBrandingEditor(branding: branding, symbol: symbol, compact: compact, showsPreview: false)
                .id(draft.id)
        case .ready:
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Spaces are ready").font(CrestTypography.display(36))
                Text("Review your Spaces or add another before opening Crest.")
                    .foregroundStyle(.secondary)
                ForEach(plan.spaces) { space in
                    Button {
                        selectedSpaceID = space.id
                        step = .appearance
                    } label: {
                        HStack(spacing: 16) {
                            BrowserSpaceEditorIdentityPreview(
                                branding: space.customization.branding, symbol: space.customization.symbol, size: 44)
                            Text(space.customization.resolvedName).font(.headline)
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
                            Button("Remove Space", role: .destructive) { model.removeSpace(space.id, plan: $plan) }
                        }
                    }
                }
                Button("Add another Space", systemImage: "plus", action: addSpace)
                    .buttonStyle(.crestSecondary)
                    .controlSize(.large)
                if opensGettingStarted {
                    Text(gettingStartedDescription)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

        }
    }

    private var gettingStartedDescription: LocalizedStringKey {
        #if os(iOS)
            "Getting Started opens next with practice for tabs and folders."
        #else
            "Getting Started opens next with practice for tabs, folders, and Split View."
        #endif
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let message = errorMessage ?? model.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button {
                    switch step {
                    case .appearance: back()
                    case .ready: step = .appearance
                    }
                } label: {
                    Label("Back", systemImage: "arrow.left")
                }
                .buttonStyle(.crestSecondary)
                Spacer()
                Button {
                    switch step {
                    case .appearance: step = .ready
                    case .ready: finish()
                    }
                } label: {
                    HStack(spacing: 20) {
                        Text(step == .ready ? "Open Crest" : "Continue")
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
        .background(chromeBackground)
        .overlay(alignment: .top) { Rectangle().fill(BrowserOnboardingPalette.line).frame(height: 1) }
    }

    private func addSpace() {
        model.addSpace(plan: $plan, selectedSpaceID: $selectedSpaceID)
        step = .appearance
    }

    private func spacePicker(for spaceID: SpaceID) -> BrowserSpaceCustomizationPicker {
        BrowserSpaceCustomizationPicker(
            spaces: plan.spaces.map { model.previewSpace(for: $0, in: nil) },
            selectedSpaceID: spaceID,
            selectSpace: {
                model.select($0, selectedSpaceID: $selectedSpaceID)
                step = .appearance
            },
            moveSpace: { plan.moveSpace($0, to: $1) }, addSpace: addSpace)
    }
}
