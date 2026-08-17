import SwiftUI

struct BrowserTabIconActions: View {
    let tab: BrowserTab
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let performIfCurrent: ((BrowserTab) -> Void) -> Void
    let clearIcon: (BrowserTab) -> Void
    let setEmoji: (BrowserTab, String) -> Void

    var body: some View {
        Button("Pull New Icon", systemImage: "arrow.clockwise.circle") {
            performIfCurrent { _ in pullNewIcon?() }
        }
        .disabled(!isLoaded || pullNewIcon == nil)

        Button("Clear Icon", systemImage: "xmark.circle") {
            performIfCurrent(clearIcon)
        }
        .disabled(tab.iconMode == .automatic && tab.faviconData == nil)

        Menu("Choose Emoji Icon", systemImage: "face.smiling") {
            ForEach(BrowserTabEmojiChoices.all) { choice in
                Button {
                    performIfCurrent { setEmoji($0, choice.emoji) }
                } label: {
                    Label {
                        Text(choice.name)
                    } icon: {
                        Text(choice.emoji)
                    }
                }
            }
        }
    }
}
