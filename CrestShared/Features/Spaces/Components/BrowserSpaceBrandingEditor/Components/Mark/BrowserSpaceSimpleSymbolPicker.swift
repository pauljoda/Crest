import SwiftUI

struct BrowserSpaceSimpleSymbolPicker: View {
    @Binding var symbol: String

    var body: some View {
        Picker("Symbol", selection: $symbol) {
            ForEach(BrowserSpaceSimpleSymbol.allCases) { option in
                Label(option.titleKey, systemImage: option.rawValue)
                    .tag(option.rawValue)
            }
        }
        .labelsHidden()
    }
}

#Preview("Simple Symbol Picker") {
    @Previewable @State var symbol = BrowserSpaceSimpleSymbol.work.rawValue

    BrowserSpaceSimpleSymbolPicker(symbol: $symbol)
        .frame(width: 240)
        .padding(CrestSpacing.large)
}
