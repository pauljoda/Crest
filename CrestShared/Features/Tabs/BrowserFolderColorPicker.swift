import SwiftUI

struct BrowserFolderColorPicker: View {
    @Binding var color: BrowserSpaceBrandColor

    private let columns = Array(
        repeating: GridItem(.fixed(28), spacing: CrestSpacing.small),
        count: 6
    )

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text("Folder Color")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: CrestSpacing.small) {
                ForEach(BrowserFolderColorPalette.choices) { choice in
                    Button {
                        color = choice.value
                    } label: {
                        Circle()
                            .fill(choice.value.color)
                            .frame(width: 22, height: 22)
                            .padding(3)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Color.primary.opacity(
                                            color == choice.value ? 0.75 : 0.14
                                        ),
                                        lineWidth: color == choice.value ? 2 : 0.5
                                    )
                            }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .help(choice.title)
                    .accessibilityLabel(choice.title)
                    .accessibilityValue(
                        color == choice.value ? "Selected" : ""
                    )
                }
            }

            Divider()

            ColorPicker(
                "Custom Color",
                selection: Binding(
                    get: { color.color },
                    set: { color = BrowserSpaceBrandColor(color: $0) }
                ),
                supportsOpacity: false
            )
        }
        .padding(CrestSpacing.large)
        .frame(width: 246)
    }
}

#Preview("Folder Color") {
    @Previewable @State var color = BrowserSpaceBrandColor.indigo
    BrowserFolderColorPicker(color: $color)
        .padding()
}
