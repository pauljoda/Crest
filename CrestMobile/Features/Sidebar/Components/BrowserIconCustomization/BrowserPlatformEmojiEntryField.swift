import SwiftUI

enum BrowserPlatformEmojiInput {
    /// The emoji button focuses the field so the emoji keyboard can come up.
    static var actionTitle: LocalizedStringKey { "Use Emoji Keyboard" }
}

struct BrowserPlatformEmojiEntryField: View {
    @Binding var text: String
    let commit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Search or Enter Emoji", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit(commit)
            .accessibilityIdentifier(BrowserMobileAccessibilityID.emojiIconField)
        BrowserNativeEmojiPickerButton { isFocused = true }
    }
}

#if DEBUG
    #Preview("Enter an emoji") {
        @Previewable @State var text = "🌊"
        BrowserPlatformEmojiEntryField(text: $text, commit: {}).padding().frame(width: 320)
    }
#endif
