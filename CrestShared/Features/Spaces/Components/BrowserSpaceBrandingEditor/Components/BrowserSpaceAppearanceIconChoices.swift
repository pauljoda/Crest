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
                            .foregroundStyle(branding.resolvedSymbolColor.color)
                            .frame(height: 64)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Or use an emoji").font(.headline)
                BrowserSpaceSimpleSymbolPicker(
                    symbol: Binding(
                        get: { symbol },
                        set: {
                            symbol = $0
                            branding.iconStyle = .simpleSymbol
                        }))
            }
            if BrowserIconSymbol.emoji(from: symbol) == nil {
                Toggle(
                    "Use theme color",
                    isOn: Binding(
                        get: { branding.symbolColor == nil },
                        set: { branding.symbolColor = $0 ? nil : branding.primaryColor }))
                if branding.symbolColor != nil {
                    ColorPicker(
                        "Symbol color",
                        selection: Binding(
                            get: { branding.resolvedSymbolColor.color },
                            set: { branding.symbolColor = BrowserSpaceBrandColor(color: $0) }
                        ), supportsOpacity: false)
                }
            }
        }
    }
}
