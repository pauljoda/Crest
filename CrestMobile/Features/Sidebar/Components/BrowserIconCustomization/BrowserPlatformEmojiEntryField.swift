import SwiftUI

enum BrowserPlatformEmojiInput {
    static let presentation = BrowserNativeEmojiPickerPresentation.focusedTextInput
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
            .accessibilityIdentifier("browser-emoji-icon-field")
        BrowserNativeEmojiPickerButton { isFocused = true }
    }
}
