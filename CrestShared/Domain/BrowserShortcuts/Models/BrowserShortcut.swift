struct BrowserShortcut: Codable, Equatable, Hashable, Sendable {
    let key: BrowserShortcutKey
    let modifiers: ShortcutModifiers

    var isValid: Bool {
        !modifiers.intersection(.supported).isEmpty
    }
}

extension BrowserShortcut {
    /// The chord a catalog default names. The catalog spells special keys the
    /// way `BrowserShortcutSpecialKey` does, and every other key as the one
    /// character it types.
    init(_ keys: KeyCombination) {
        let key: BrowserShortcutKey
        if keys.isSpecialKey {
            guard let special = BrowserShortcutSpecialKey(rawValue: keys.key) else {
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

enum BrowserShortcutSpecialKey:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case tab
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case escape
    case returnKey
    case delete
    case forwardDelete
    case home
    case end
    case pageUp
    case pageDown
    case space
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case f13
    case f14
    case f15
    case f16
    case f17
    case f18
    case f19
    case f20
}
