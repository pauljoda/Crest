import SwiftUI

/// An emblem drawn from an emoji.
struct BrowserCrestStudioEmojiEmblem: BrowserCrestStudioEmblemSource {
    // MARK: - Actions - Controls

    func controls(in emblem: BrowserCrestStudioEmblem) -> AnyView {
        AnyView(
            BrowserArtworkPickerButton(title: "Emoji", detail: Text("Change emoji")) {
                emblem.choosesEmoji = true
            } artwork: {
                Text(emblem.emoji)
            }
            .accessibilityLabel("Choose Emoji")
            .accessibilityValue(emblem.emoji)
            .browserIconCustomizationPopover(
                .init(
                    isPresented: emblem.$choosesEmoji, title: "Emblem", currentEmoji: emblem.emoji,
                    setEmoji: { emblem.emoji = $0 })))
    }

    // MARK: - Actions - Charge

    func charge(in emblem: BrowserCrestStudioEmblem) -> CrestCharge {
        .emoji(emblem.emoji)
    }

    func load(_ charge: CrestCharge, into emblem: BrowserCrestStudioEmblem) {
        let text = charge.text ?? ""
        if emblem.emoji != text { emblem.emoji = text }
    }
}
