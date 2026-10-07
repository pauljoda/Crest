import SwiftUI

struct BrowserCrestStudioEmblem: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    /// Shows the controls without their card or color row, for a studio
    /// that frames them and paints the emblem elsewhere.
    let isEmbedded: Bool
    @State private var source: CrestChargeKind
    @State private var search = ""
    @State private var showsAll = false
    @State private var systemName = "sparkles"
    @State private var emoji = "🦁"
    @State private var monogram = "C"
    @State private var monogramStyle = CrestMonogramStyle.serif
    @State private var choosesEmoji = false

    init(context: BrowserCrestStudioContext, symbol: String, isEmbedded: Bool = false) {
        self.context = context
        self.symbol = symbol
        self.isEmbedded = isEmbedded
        _source = State(initialValue: context.value.crest.resolvedCharge.kind)
    }

    var body: some View {
        Group {
            if isEmbedded {
                VStack(alignment: .leading, spacing: 16) { controls }
            } else {
                BrowserCrestStudioGroup(step: .emblem, preview: context.compact ? context.value : nil, symbol: symbol) {
                    controls
                }
            }
        }
        .onAppear { load(context.value.crest.resolvedCharge) }
        .onChange(of: source) { _, _ in commitSource() }
        .onChange(of: context.value.crest.resolvedCharge) { _, charge in
            // Empty in-progress text stays editable instead of removing its field.
            if charge != CrestCharge.none { load(charge) }
        }
        .onChange(of: systemName) { _, _ in if source == .system { commitSource() } }
        .onChange(of: emoji) { _, _ in if source == .emoji { commitSource() } }
        .onChange(of: monogram) { _, _ in if source == .monogram { commitSource() } }
        .onChange(of: monogramStyle) { _, _ in if source == .monogram { commitSource() } }
    }

    @ViewBuilder private var controls: some View {
        let value = context.crest(\.charge)
        CrestSettingRow("Source", setting: value.resettable("Emblem")) {
            Picker("Emblem source", selection: $source) {
                ForEach(CrestChargeKind.all, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().fixedSize()
        }
        sourceControls
        if source != .none {
            if source.isTinted, !isEmbedded {
                BrowserCrestStudioColorRow(context: context, title: "Emblem color", path: \.symbolColorIndex)
            }
            context.picker("Arrangement", \.chargeLayout, options: CrestChargeLayout.all)
            context.slider("Size", \.chargeScale, range: CrestMeasure.chargeScale.range)
            context.slider("Vertical offset", \.chargeOffset, range: CrestMeasure.chargeOffset.range)
            if source.takesWeight, source != .heraldic || context.value.crest.symbol.assetName == nil {
                context.picker("Weight", \.chargeWeight, options: CrestChargeWeight.all)
            }
        }
    }

    @ViewBuilder private var sourceControls: some View {
        switch source.kind {
        case .heraldic:
            BrowserCrestStudioTextField(title: "Find an emblem", symbol: "magnifyingglass", text: $search)
            let matches = CrestSymbol.selectable.filter {
                search.isEmpty || String(localized: $0.title).localizedCaseInsensitiveContains(search)
            }
            let visible = search.isEmpty && !showsAll ? Array(matches.prefix(12)) : matches
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 8) {
                ForEach(visible, id: \.self) { choice in
                    BrowserCrestStudioChoice(
                        title: choice.title, selected: context.value.crest.resolvedCharge == .heraldic(choice)
                    ) {
                        context.branding.editorUpdate {
                            $0.crest.symbol = choice
                            $0.crest.charge = nil
                            $0.hasCustomAppearance = true
                        }
                    } artwork: {
                        BrowserSpaceCrestIcon(
                            branding: context.preview {
                                $0.crest.symbol = choice
                                $0.crest.charge = nil
                            }, size: 52, rasterizesLayers: false
                        )
                        .equatable()
                    }
                }
            }
            if search.isEmpty && matches.count > 12 {
                Button(showsAll ? "Show fewer emblems" : "Browse all emblems (\(matches.count))") { showsAll.toggle() }
                    .buttonStyle(.borderless)
            } else if matches.isEmpty {
                Text("No matching emblems. Try an SF Symbol or a monogram.").font(.caption).foregroundStyle(.secondary)
            }
        case .system:
            BrowserSystemSymbolPicker(selection: $systemName)
        case .emoji:
            BrowserArtworkPickerButton(title: "Emoji", detail: Text("Change emoji")) {
                choosesEmoji = true
            } artwork: {
                Text(emoji)
            }
            .accessibilityLabel("Choose Emoji")
            .accessibilityValue(emoji)
            .browserIconCustomizationPopover(
                .init(
                    isPresented: $choosesEmoji, title: "Emblem", currentEmoji: emoji,
                    setEmoji: { emoji = $0 }))
        case .monogram:
            BrowserCrestStudioTextField(title: "One or two letters", text: $monogram)
            Picker("Letter style", selection: $monogramStyle) {
                Text("Serif").tag(CrestMonogramStyle.serif)
                Text("Sans").tag(CrestMonogramStyle.sans)
            }.pickerStyle(.segmented)
        case .none: EmptyView()
        }
    }

    private func commitSource() {
        let charge: CrestCharge
        switch source.kind {
        case .heraldic: charge = .heraldic(context.value.crest.symbol)
        case .system: charge = .system(systemName)
        case .emoji: charge = .emoji(emoji)
        case .monogram: charge = .monogram(monogram, monogramStyle)
        case .none: charge = CrestCharge.none
        }
        context.crest(\.charge).binding.wrappedValue = charge
    }

    private func load(_ charge: CrestCharge) {
        source = charge.kind
        let text = charge.text ?? ""
        switch charge.kind.kind {
        case .system: if systemName != text { systemName = text }
        case .emoji: if emoji != text { emoji = text }
        case .monogram:
            if monogram != text { monogram = text }
            monogramStyle = charge.style ?? .serif
        default: break
        }
    }
}

#if DEBUG
    #Preview("Interactive crest controls") {
        @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
        Form {
            BrowserCrestStudioEmblem(
                context: BrowserCrestStudioContext(
                    branding: $branding, defaults: BrowserSpaceBrandingPreviewFixture.crestBranding, compact: false),
                symbol: "crown.fill")
        }.crestSettingsForm().frame(width: 480, height: 650)
    }
#endif
