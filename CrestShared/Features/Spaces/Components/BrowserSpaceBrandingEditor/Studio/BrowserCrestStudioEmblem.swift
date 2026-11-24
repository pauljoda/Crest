import SwiftUI

/// A crest's emblem: a heraldic figure, a symbol, an emoji or a monogram, and
/// how many of it the crest carries. The stage paints it.
struct BrowserCrestStudioEmblem: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    @State private var source: CrestChargeKind
    // The fields each emblem source edits, kept while another source is shown.
    @State var search = ""
    @State var showsAll = false
    @State var systemName = "sparkles"
    @State var emoji = "🦁"
    @State var monogram = "C"
    @State var monogramStyle = CrestMonogramStyle.serif
    @State var choosesEmoji = false

    init(context: BrowserCrestStudioContext, symbol: String) {
        self.context = context
        self.symbol = symbol
        _source = State(initialValue: context.value.crest.resolvedCharge.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) { controls }
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
            context.picker("Arrangement", \.chargeLayout, options: CrestChargeLayout.offered)
        }
    }

    @ViewBuilder private var sourceControls: some View {
        switch source.kind {
        case .heraldic:
            BrowserCrestStudioHeraldicEmblemControls(context: context, search: $search, showsAll: $showsAll)
        case .system:
            BrowserSystemSymbolPicker(selection: $systemName)
        case .emoji:
            BrowserCrestStudioEmojiEmblemControls(emoji: $emoji, choosesEmoji: $choosesEmoji)
        case .monogram:
            BrowserCrestStudioMonogramEmblemControls(monogram: $monogram, monogramStyle: $monogramStyle)
        case .none:
            EmptyView()
        }
    }

    private func commitSource() {
        context.crest(\.charge).binding.wrappedValue = source.studioSource.charge(in: self)
    }

    private func load(_ charge: CrestCharge) {
        source = charge.kind
        charge.kind.studioSource.load(charge, into: self)
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
