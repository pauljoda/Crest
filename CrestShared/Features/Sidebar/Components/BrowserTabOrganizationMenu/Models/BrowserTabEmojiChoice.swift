struct BrowserTabEmojiChoice: Identifiable {
    let emoji: String
    let name: String

    var id: String { emoji }
}
