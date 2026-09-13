import SwiftUI

struct BrowserIconSelectionGrid: View {
    let mode: BrowserIconPickerMode
    let emojiChoices: [BrowserTabEmojiChoice]
    let systemSymbols: [BrowserIconSystemChoice]
    let currentEmoji: String?
    let currentSystemSymbol: String?
    let selectEmoji: (String) -> Void
    let selectSystemSymbol: (String) -> Void

    @State private var variantChoice: BrowserTabEmojiChoice?

    @ViewBuilder
    var body: some View {
        if visibleChoiceCount == 0 {
            Text(mode == .emoji ? "No Matching Emoji" : "No Matching Icons")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: BrowserIconPickerLayout.contentWidth, height: BrowserIconPickerLayout.emptyGridHeight)
                .accessibilityIdentifier("browser-icon-picker-empty")
        } else {
            ScrollView {
                LazyVGrid(columns: BrowserIconPickerLayout.columns, spacing: BrowserIconPickerLayout.gridSpacing) {
                    if mode == .emoji {
                        ForEach(emojiChoices) { choice in
                            BrowserIconEmojiButton(
                                choice: choice, currentEmoji: currentEmoji,
                                variantChoice: $variantChoice, selectEmoji: selectEmoji)
                        }
                    } else {
                        ForEach(systemSymbols) { choice in
                            BrowserIconSystemSymbolButton(
                                choice: choice, currentSymbol: currentSystemSymbol, select: selectSystemSymbol)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(
                width: BrowserIconPickerLayout.contentWidth,
                height: BrowserIconPickerLayout.gridHeight(choiceCount: visibleChoiceCount))
        }
    }

    private var visibleChoiceCount: Int {
        mode == .emoji ? emojiChoices.count : systemSymbols.count
    }
}
