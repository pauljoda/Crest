import SwiftUI

struct BrowserIconSearchField: View {
    let mode: BrowserIconPickerMode
    @Binding var query: String
    let commitEmoji: () -> Void

    var body: some View {
        CrestSearchField(text: $query) {
            if mode == .emoji {
                BrowserPlatformEmojiEntryField(text: $query, commit: commitEmoji)
            } else {
                TextField("Search Icons", text: $query)
                    .accessibilityIdentifier("browser-icon-search-field")
            }
        }
        .onChange(of: mode) { _, _ in query = "" }
    }
}

struct BrowserNativeEmojiPickerButton: View {
    let action: () -> Void

    var body: some View {
        Button(
            BrowserPlatformEmojiInput.actionTitle,
            systemImage: "face.smiling", action: action
        )
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .frame(width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget)
        .contentShape(.rect)
        .accessibilityHint("Inserts any emoji through the system text input experience.")
    }
}

#if DEBUG
    #Preview("Search icons") {
        @Previewable @State var query = ""
        BrowserIconSearchField(mode: .emoji, query: $query, commitEmoji: {}).padding().frame(width: 340)
    }
#endif
