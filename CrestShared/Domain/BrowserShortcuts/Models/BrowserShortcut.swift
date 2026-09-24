struct BrowserShortcut: Codable, Equatable, Hashable, Sendable {
    let key: BrowserShortcutKey
    let modifiers: ShortcutModifiers

    var isValid: Bool {
        !modifiers.intersection(.supported).isEmpty
    }
}

extension BrowserShortcut {
    /// The chord a catalog default names. The catalog names a special key by
    /// its `ShortcutSpecialKey` name, and every other key as the one character
    /// it types.
    init(_ keys: KeyCombination) {
        let key: BrowserShortcutKey
        if keys.isSpecialKey {
            guard let special = ShortcutSpecialKey.named(keys.key) else {
                preconditionFailure("The shortcut catalog names an unknown special key \(keys.key)")
            }
            key = .special(special)
        } else {
            guard keys.key.count == 1, let character = keys.key.first else {
                preconditionFailure("The shortcut catalog's key \(keys.key) is not one character")
            }
            key = .character(character)
        }
        self.init(key: key, modifiers: keys.modifiers)
    }
}

enum BrowserShortcutAssignmentResult: Equatable, Sendable {
    case assigned
    case conflict(commands: [ShortcutCommand])
    case invalid
}

enum BrowserShortcutKey: Codable, Hashable, Sendable {
    case character(Character)
    case special(ShortcutSpecialKey)

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
                ShortcutSpecialKey.self,
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

/// A modifier mask persists as its raw bits.
extension ShortcutModifiers: Codable, Hashable {
    static let supported: ShortcutModifiers = [
        .command,
        .option,
        .control,
        .shift,
    ]
}

enum BrowserShortcutOverride: Equatable, Sendable {
    case custom(BrowserShortcut)
    case unassigned
}

struct BrowserShortcutSearchDocument: Equatable, Sendable {
    let fields: [String]
}

extension ShortcutSection: Identifiable {
    var id: String { name }
}
