import SwiftUI

/// What a Space wears as its icon: a crest, or a plain symbol or emoji.
struct BrowserSpaceIconKind: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let crest = BrowserSpaceIconKind(name: "crest", title: "Crest")
    static let symbol = BrowserSpaceIconKind(name: "symbol", title: "Symbol")
    static let emoji = BrowserSpaceIconKind(name: "emoji", title: "Emoji")

    static let all: [BrowserSpaceIconKind] = [crest, symbol, emoji]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource

    var id: String { name }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource) {
        self.name = name
        self.title = title
    }

    // MARK: - Functions

    /// The kind of icon a Space wearing `branding` and `symbol` shows.
    static func worn(by branding: SpaceBranding, symbol: String) -> BrowserSpaceIconKind {
        if branding.iconStyle == .layeredCrest { return .crest }
        return BrowserIconSymbol.emoji(from: symbol) == nil ? .symbol : .emoji
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpaceIconKind, rhs: BrowserSpaceIconKind) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// A Space's icon: a crest, started from one of the houses, which also sets
/// the Space's Background and Accent, or a plain symbol or emoji in the
/// Accent. Setup's Space page and a Space's appearance in Settings both show
/// it.
struct BrowserSpaceIconPicker: View {
    // MARK: - Variables

    @Binding var branding: SpaceBranding
    @Binding var symbol: String

    /// The kind picked, which may run ahead of the Space while a person
    /// chooses their first emoji.
    @State private var kind: BrowserSpaceIconKind?
    @State private var choosesEmoji = false

    private var shownKind: BrowserSpaceIconKind {
        kind ?? BrowserSpaceIconKind.worn(by: branding, symbol: symbol)
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Picker("Icon", selection: Binding(get: { shownKind }, set: choose)) {
            ForEach(BrowserSpaceIconKind.all) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("space-icon-kind")
        content
            .onChange(of: branding.iconStyle) { _, _ in kind = nil }
            .onChange(of: symbol) { _, _ in kind = nil }
    }

    @ViewBuilder private var content: some View {
        if shownKind == .crest {
            starterCrests
        } else if shownKind == .symbol {
            BrowserSystemSymbolPicker(
                selection: Binding(
                    get: { BrowserIconSymbol.emoji(from: symbol) == nil ? symbol : "" },
                    set: { wear($0) }))
        } else {
            emojiButton
        }
    }

    /// The houses' crests, simple then heraldic, each in its own colors and
    /// nothing of the Space's, so editing the Space never redraws them:
    /// choosing one gives the Space its crest, Background and Accent.
    private var starterCrests: some View {
        VStack(alignment: .leading, spacing: BrowserSpaceIconPickerMetrics.styleSpacing) {
            ForEach(SpaceHouseStyle.all, id: \.self) { style in
                VStack(alignment: .leading, spacing: CrestSpacing.small) {
                    Text(style.title)
                        .crestCapsLabel()
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 80), spacing: CrestSpacing.small)],
                        spacing: CrestSpacing.small
                    ) {
                        ForEach(SpaceHouse.all.filter { $0.style == style }, id: \.self) { house in
                            crest(of: house)
                        }
                    }
                }
            }
        }
        .padding(.vertical, CrestSpacing.extraSmall)
        .accessibilityIdentifier("space-starter-crests")
    }

    private func crest(of house: SpaceHouse) -> some View {
        BrowserCrestStudioChoice(title: house.title, selected: house.isWorn(by: branding)) {
            branding = house.applying(to: branding)
        } artwork: {
            BrowserSpaceCrestIcon(
                branding: Self.starterLook(of: house), size: BrowserCrestForgeMetrics.tileCrestSize,
                rasterizesLayers: false
            )
            .equatable()
        }
    }

    /// `house`'s own look wearing its crest.
    private static func starterLook(of house: SpaceHouse) -> SpaceBranding {
        var look = house.look
        look.iconStyle = .layeredCrest
        return look
    }

    private var emojiButton: some View {
        BrowserArtworkPickerButton(
            title: "Emoji",
            detail: BrowserIconSymbol.emoji(from: symbol) == nil ? Text("Choose an emoji") : Text("Change emoji")
        ) {
            choosesEmoji = true
        } artwork: {
            if let emoji = BrowserIconSymbol.emoji(from: symbol) {
                Text(emoji)
            } else {
                Image(systemName: "face.smiling")
            }
        }
        .accessibilityLabel("Choose Emoji")
        .browserIconCustomizationPopover(
            .init(
                isPresented: $choosesEmoji, title: "Space Icon",
                currentEmoji: BrowserIconSymbol.emoji(from: symbol),
                setEmoji: { wear(BrowserIconSymbol.symbol(forEmoji: $0)) }))
    }

    // MARK: - Mutators

    /// Shows `kind`: a crest at once, a symbol in place of an emoji, and the
    /// emoji picker for an emoji.
    private func choose(_ kind: BrowserSpaceIconKind) {
        if kind == .crest {
            self.kind = nil
            $branding.editorUpdate {
                $0.iconStyle = .layeredCrest
                $0.hasCustomAppearance = true
            }
        } else if kind == .symbol {
            self.kind = nil
            wear(BrowserIconSymbol.emoji(from: symbol) == nil ? symbol : BrowserSpaceIconPickerMetrics.symbol)
        } else {
            self.kind = kind
            choosesEmoji = true
        }
    }

    /// Gives the Space `symbol` as its plain icon.
    private func wear(_ symbol: String) {
        self.symbol = symbol
        guard branding.iconStyle != .simpleSymbol else { return }
        $branding.editorUpdate {
            $0.iconStyle = .simpleSymbol
            $0.hasCustomAppearance = true
        }
    }
}

enum BrowserSpaceIconPickerMetrics {
    /// The symbol a Space trading its emoji for a symbol starts from.
    static let symbol = "sparkles"
    /// The room between the simple and heraldic crests, and under each name.
    static let styleSpacing: CGFloat = 14
}

#if DEBUG
    #Preview("Space icon") {
        @Previewable @State var branding = SpaceHouse.winter.look
        @Previewable @State var symbol = "briefcase.fill"
        Form {
            Section {
                BrowserSpaceIconPicker(branding: $branding, symbol: $symbol)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
#endif
