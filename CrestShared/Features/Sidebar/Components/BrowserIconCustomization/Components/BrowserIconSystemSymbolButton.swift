import SwiftUI

struct BrowserIconSystemSymbolButton: View {
    let choice: BrowserIconSystemChoice
    let currentSymbol: String?
    let select: (String) -> Void

    var body: some View {
        Button {
            select(choice.symbol)
        } label: {
            Image(systemName: choice.symbol)
                .font(.title3)
                .frame(width: BrowserIconPickerLayout.cellSize, height: BrowserIconPickerLayout.cellSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            currentSymbol == choice.symbol ? CrestColor.hover : .clear,
            in: .rect(cornerRadius: CrestRadius.compact)
        )
        .help(Text(choice.title))
        .accessibilityLabel(Text(choice.title))
        .accessibilityValue(
            currentSymbol == choice.symbol ? "Selected" : ""
        )
    }

}
