struct BrowserShortcut: Codable, Equatable, Hashable, Sendable {
    let key: BrowserShortcutKey
    let modifiers: BrowserShortcutModifiers

    var isValid: Bool {
        !modifiers.intersection(.supported).isEmpty
    }
}

enum BrowserShortcutAssignmentResult: Equatable, Sendable {
    case assigned
    case conflict(commands: [BrowserShortcutCommand])
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

struct BrowserShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let command = BrowserShortcutModifiers(rawValue: 1 << 0)
    static let option = BrowserShortcutModifiers(rawValue: 1 << 1)
    static let control = BrowserShortcutModifiers(rawValue: 1 << 2)
    static let shift = BrowserShortcutModifiers(rawValue: 1 << 3)

    static let supported: BrowserShortcutModifiers = [
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

enum BrowserShortcutSection: String, CaseIterable, Identifiable, Sendable {
    case everyday
    case tabs
    case spaces
    case page
    case view

    var id: Self { self }
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
