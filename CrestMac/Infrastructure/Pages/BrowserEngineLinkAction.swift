import Foundation

/// A link action an engine's own context menu or drag asks the page about.
/// The `can` cases answer whether the menu offers the item; the others run it.
enum BrowserEngineLinkAction {
    case canSearch, search
    case canPeek, peek
    case canSplit, split
    case drag
}

/// The modifier keys and button that activated a link in the engine.
struct BrowserEngineLinkModifiers: OptionSet {
    let rawValue: Int
    static let command = Self(rawValue: 1)
    static let option = Self(rawValue: 2)
    static let shift = Self(rawValue: 4)
    static let middleClick = Self(rawValue: 8)
}
