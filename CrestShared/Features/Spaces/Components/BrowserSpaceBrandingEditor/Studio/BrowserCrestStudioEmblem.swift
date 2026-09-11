import SwiftUI

struct BrowserCrestStudioEmblem: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    @State private var source: Source
    @State private var search = ""
    @State private var showsAll = false
    @State private var systemName = "sparkles"
    @State private var emoji = "🦁"
    @State private var monogram = "C"
    @State private var monogramStyle = BrowserSpaceCrestMonogramStyle.serif
    @State private var choosesEmoji = false

    private enum Source: String, CaseIterable {
        case heraldic = "Heraldry"
        case system = "SF Symbol"
        case emoji = "Emoji"
        case monogram = "Monogram"
        case none = "None"
        init(_ charge: BrowserSpaceCrestCharge) {
            switch charge {
            case .heraldic: self = .heraldic
            case .system: self = .system
            case .emoji: self = .emoji
            case .monogram: self = .monogram
            case .none: self = .none
            }
        }
    }

    init(context: BrowserCrestStudioContext, symbol: String) {
        self.context = context
        self.symbol = symbol
        _source = State(initialValue: Source(context.value.crest.resolvedCharge))
    }

    var body: some View {
        BrowserCrestStudioGroup(title: "Emblem", preview: context.compact ? context.value : nil, symbol: symbol) {
            let value = context.crest(\.charge)
            CrestSettingRow("Source", setting: value.resettable("Emblem")) {
                Picker("Emblem source", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }.labelsHidden().fixedSize()
            }
            sourceControls
            if source != .none {
                if source != .emoji {
                    BrowserCrestStudioColorRow(context: context, title: "Emblem color", path: \.symbolColorIndex)
                }
                context.picker("Arrangement", \.chargeLayout, options: BrowserSpaceCrestChargeLayout.allCases)
                context.slider("Size", \.chargeScale, range: BrowserSpaceCrest.chargeScaleRange)
                context.slider("Vertical offset", \.chargeOffset, range: BrowserSpaceCrest.chargeOffsetRange)
                if source == .system || source == .monogram
                    || (source == .heraldic && context.value.crest.symbol.assetName == nil)
                {
                    context.picker("Weight", \.chargeWeight, options: BrowserSpaceCrestChargeWeight.allCases)
                }
            }
        }
        .onAppear { load(context.value.crest.resolvedCharge) }
        .onChange(of: source) { _, _ in commitSource() }
        .onChange(of: context.value.crest.resolvedCharge) { _, charge in
            // Empty in-progress text stays editable instead of removing its field.
            if charge != .none { load(charge) }
        }
        .onChange(of: systemName) { _, _ in if source == .system { commitSource() } }
        .onChange(of: emoji) { _, _ in if source == .emoji { commitSource() } }
        .onChange(of: monogram) { _, _ in if source == .monogram { commitSource() } }
        .onChange(of: monogramStyle) { _, _ in if source == .monogram { commitSource() } }
    }

    @ViewBuilder private var sourceControls: some View {
        switch source {
        case .heraldic:
            BrowserCrestStudioTextField(title: "Find an emblem", symbol: "magnifyingglass", text: $search)
            let matches = BrowserSpaceCrestSymbol.selectable.filter {
                search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            }
            let visible = search.isEmpty && !showsAll ? Array(matches.prefix(12)) : matches
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 8) {
                ForEach(visible, id: \.self) { choice in
                    BrowserCrestStudioChoice(
                        title: choice.titleKey, selected: context.value.crest.resolvedCharge == .heraldic(choice)
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
                Text("Serif").tag(BrowserSpaceCrestMonogramStyle.serif)
                Text("Sans").tag(BrowserSpaceCrestMonogramStyle.sans)
            }.pickerStyle(.segmented)
        case .none: EmptyView()
        }
    }

    private func commitSource() {
        let charge: BrowserSpaceCrestCharge
        switch source {
        case .heraldic: charge = .heraldic(context.value.crest.symbol)
        case .system: charge = .system(systemName)
        case .emoji: charge = .emoji(emoji)
        case .monogram: charge = .monogram(monogram, monogramStyle)
        case .none: charge = .none
        }
        context.crest(\.charge).binding.wrappedValue = charge
    }

    private func load(_ charge: BrowserSpaceCrestCharge) {
        source = Source(charge)
        switch charge {
        case .system(let name): if systemName != name { systemName = name }
        case .emoji(let text): if emoji != text { emoji = text }
        case .monogram(let text, let style):
            if monogram != text { monogram = text }
            monogramStyle = style
        default: break
        }
    }
}
