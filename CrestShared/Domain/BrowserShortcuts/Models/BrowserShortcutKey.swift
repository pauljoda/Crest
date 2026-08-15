enum BrowserShortcutKey: Codable, Hashable, Sendable {
    case character(Character)
    case special(BrowserShortcutSpecialKey)

    private enum CodingKeys: String, CodingKey {
        case character
        case special
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(
            String.self,
            forKey: .character
        ),
            value.count == 1,
            let character = value.first
        {
            self = .character(character)
            return
        }
        self = .special(
            try container.decode(
                BrowserShortcutSpecialKey.self,
                forKey: .special
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .character(let character):
            try container.encode(String(character), forKey: .character)
        case .special(let key):
            try container.encode(key, forKey: .special)
        }
    }
}
