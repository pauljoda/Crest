import SwiftUI

struct BrowserCommandPaletteSearchField: View {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let queryIsFocused: FocusState<Bool>.Binding

    @ScaledMetric private var fieldHeight: CGFloat

    init(
        model: BrowserCommandPaletteModel, presentation: BrowserCommandPalettePresentation,
        queryIsFocused: FocusState<Bool>.Binding
    ) {
        self.model = model
        self.presentation = presentation
        self.queryIsFocused = queryIsFocused
        _fieldHeight = ScaledMetric(
            wrappedValue: presentation.input.fieldHeight, relativeTo: presentation.input.textStyle)
    }

    var body: some View {
        HStack(spacing: BrowserCommandPaletteMetrics.searchFieldSpacing) {
            if presentation.input.showsSearchGlyph {
                Image(systemName: "magnifyingglass")
                    .font(.system(presentation.input.textStyle, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            activeChip

            BrowserPlatformCommandPaletteField(
                model: model,
                presentation: presentation,
                identifier: presentation.fieldIdentifier,
                focused: queryIsFocused.wrappedValue
            )
            .focused(queryIsFocused)
            .frame(height: fieldHeight)

            offer

            if presentation.showsCloseButton {
                Button("Close", systemImage: "xmark", action: model.dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, presentation.input.horizontalPadding)
        .frame(minHeight: presentation.input.minimumHeight)
    }

    /// The search provider or scope the palette is narrowed to, which leaves
    /// it when clicked.
    @ViewBuilder
    private var activeChip: some View {
        if let provider = model.activeProvider {
            Button {
                model.leaveScope()
            } label: {
                BrowserSearchProviderPill(
                    provider: provider, showsCloseControl: true, isInteractive: true, profileID: model.space?.profileID)
            }
            .buttonStyle(.plain)
            .help("Stop searching \(provider.title)")
            .accessibilityLabel("Stop searching \(provider.title)")
            .accessibilityIdentifier("command-palette-provider-token")
        } else if let scope = model.activeScope {
            Button {
                model.leaveScope()
            } label: {
                BrowserPaletteScopeChip(scope: scope, showsCloseControl: true, isInteractive: true)
            }
            .buttonStyle(.plain)
            .help("Show all results")
            .accessibilityLabel(Text("Stop searching \(Text(scope.title))"))
            .accessibilityIdentifier("command-palette-scope-token")
        }
    }

    /// What Tab does next: enter the provider whose shortcut the text is,
    /// accept the completion, or enter the provider or scope the text names.
    @ViewBuilder
    private var offer: some View {
        if let provider = model.providerOffer {
            Button {
                model.enter(provider)
            } label: {
                HStack(spacing: CrestSpacing.small) {
                    BrowserSearchProviderPill(
                        provider: provider, isInteractive: true, profileID: model.space?.profileID)
                    tabHint
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Press Tab to \(provider.actionTitle)")
            .accessibilityLabel(Text(verbatim: provider.actionTitle))
            .accessibilityHint("Press Tab, enter your query, then press Return.")
            .accessibilityIdentifier("command-palette-provider-offer")
        } else if let completion = model.urlCompletion {
            Button {
                model.acceptURLCompletion()
            } label: {
                tabHint
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Accept URL completion (Tab or Right Arrow)")
            .accessibilityLabel("Accept URL completion")
            .accessibilityValue(completion.accepted)
            .accessibilityHint("Fills the address without opening it. Press Tab or Right Arrow to accept.")
            .accessibilityIdentifier("command-palette-accept-completion")
        } else if let scope = model.scopeOffer {
            Button {
                model.enter(scope)
            } label: {
                HStack(spacing: CrestSpacing.small) {
                    BrowserPaletteScopeChip(scope: scope, isInteractive: true)
                    tabHint
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Search \(Text(scope.title))"))
            .accessibilityIdentifier("command-palette-scope-offer")
        }
    }

    private var tabHint: some View {
        #if os(macOS)
            Label("Tab", systemImage: "arrow.right.to.line")
                .font(.caption)
        #else
            Image(systemName: "arrow.right.to.line")
        #endif
    }
}

#if DEBUG
    #Preview("Search field") {
        @Previewable @FocusState var focused: Bool
        BrowserCommandPaletteSearchField(
            model: BrowserCommandPalettePreviewFixture.model(query: "swift"), presentation: .overlay,
            queryIsFocused: $focused
        )
        .padding().frame(width: 600)
    }
#endif
