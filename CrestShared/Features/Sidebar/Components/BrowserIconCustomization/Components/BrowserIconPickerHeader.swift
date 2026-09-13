import SwiftUI

struct BrowserIconPickerHeader: View {
    let title: LocalizedStringKey
    let showsSystemSymbols: Bool
    @Binding var mode: BrowserIconPickerMode
    let showsReset: Bool
    let resetTitle: LocalizedStringKey?
    let reset: (() -> Void)?

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            if !showsSystemSymbols {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Icon Type", selection: $mode) {
                    Text("Emoji").tag(BrowserIconPickerMode.emoji)
                    Text("Icon").tag(BrowserIconPickerMode.systemSymbol)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if showsReset, let resetTitle, let reset {
                Button {
                    reset()
                } label: {
                    Image(systemName: "trash")
                        .frame(
                            width: CrestLayout.minimumHitTarget,
                            height: CrestLayout.minimumHitTarget
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .transition(.scale(scale: BrowserIconPickerLayout.resetTransitionScale).combined(with: .opacity))
                .help(Text(resetTitle))
                .accessibilityLabel(Text(resetTitle))
                .accessibilityIdentifier("browser-icon-picker-reset")
            }
        }
    }

}
