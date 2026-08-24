import SwiftUI

struct BrowserSpaceSimpleSymbolPicker: View {
    @Binding var symbol: String
    @State private var isChoosingEmoji = false

    var body: some View {
        Button {
            isChoosingEmoji = true
        } label: {
            Group {
                if let emoji = currentEmoji {
                    Text(emoji)
                        .font(.title3)
                } else {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(
                width: CrestLayout.minimumHitTarget,
                height: CrestLayout.minimumHitTarget
            )
            .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Choose Space Icon")
        .browserIconCustomizationPopover(
            BrowserIconCustomizationPresentation(
                isPresented: $isChoosingEmoji,
                title: "Space Icon",
                currentEmoji: currentEmoji,
                currentSystemSymbol: currentEmoji == nil ? symbol : nil,
                systemSymbols: BrowserSpaceSimpleSymbol.allCases.map {
                    BrowserIconSystemChoice(
                        symbol: $0.rawValue,
                        title: $0.titleKey
                    )
                },
                setEmoji: {
                    symbol = BrowserIconSymbol.symbol(forEmoji: $0)
                },
                setSystemSymbol: { symbol = $0 }
            )
        )
    }

    private var currentEmoji: String? {
        BrowserIconSymbol.emoji(from: symbol)
    }
}
