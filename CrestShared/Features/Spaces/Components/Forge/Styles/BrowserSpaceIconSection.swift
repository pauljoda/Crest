import SwiftUI

/// A Space's plain icon under its heading, as a symbol or an emoji.
struct BrowserSpaceIconSection: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String

    var body: some View {
        Section {
            BrowserSpaceIconChoice(branding: $branding, symbol: $symbol)
        } header: {
            CrestSettingsSectionHeading(title: "Icon")
        }
    }
}

/// The controls that give a Space a plain icon: a symbol picker and an emoji
/// button. Choosing one gives a Space that wore its crest the icon in its
/// place. Each caller lays the two out as its page does.
struct BrowserSpaceIconChoice: View {
    // MARK: - Variables

    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    @State private var choosesEmoji = false

    // MARK: - Actions - Drawing

    var body: some View {
        BrowserSystemSymbolPicker(
            selection: Binding(
                get: { BrowserIconSymbol.emoji(from: symbol) == nil ? symbol : "" },
                set: { wear($0) }))
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

#if DEBUG
    #Preview("Icon choice") {
        @Previewable @State var branding = SpaceHouse.winter.look
        @Previewable @State var symbol = "briefcase.fill"
        Form {
            Section {
                BrowserSpaceIconChoice(branding: $branding, symbol: $symbol)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
    }
#endif
