import SwiftUI

struct BrowserSpaceAppearanceIconChoices: View {
    @Binding var branding: BrowserSpaceBranding
    @Binding var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 14)], spacing: 14) {
                ForEach(BrowserSpaceSimpleSymbol.allCases) { choice in
                    BrowserSpaceOptionCard(
                        title: choice.titleKey,
                        isSelected: branding.iconStyle == .simpleSymbol && symbol == choice.rawValue,
                        tint: .accentColor,
                        select: {
                            symbol = choice.rawValue
                            branding.iconStyle = .simpleSymbol
                        }
                    ) {
                        Image(systemName: choice.rawValue)
                            .font(.system(size: 32, weight: .medium))
                            .frame(height: 64)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Or use an emoji").font(.headline)
                TextField(
                    "Emoji",
                    text: Binding(
                        get: { BrowserIconSymbol.emoji(from: symbol) ?? "" },
                        set: { value in
                            guard let emoji = value.first else { return }
                            symbol = BrowserIconSymbol.symbol(forEmoji: String(emoji))
                            branding.iconStyle = .simpleSymbol
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.title)
                .frame(maxWidth: 120)
            }
        }
    }
}
