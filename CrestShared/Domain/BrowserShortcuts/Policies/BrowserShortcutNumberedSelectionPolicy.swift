enum BrowserShortcutNumberedSelectionPolicy {
    static func tabCommand(_ number: Int) -> BrowserShortcutCommand? {
        command(at: number, in: tabCommands)
    }

    static func spaceCommand(_ number: Int) -> BrowserShortcutCommand? {
        command(at: number, in: spaceCommands)
    }

    static func tabNumber(for command: BrowserShortcutCommand) -> Int? {
        tabCommands.firstIndex(of: command).map { $0 + 1 }
    }

    static func spaceNumber(for command: BrowserShortcutCommand) -> Int? {
        spaceCommands.firstIndex(of: command).map { $0 + 1 }
    }

    private static func command(
        at oneBasedIndex: Int,
        in commands: [BrowserShortcutCommand]
    ) -> BrowserShortcutCommand? {
        let index = oneBasedIndex - 1
        guard commands.indices.contains(index) else { return nil }
        return commands[index]
    }

    private static let tabCommands: [BrowserShortcutCommand] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
        .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]

    private static let spaceCommands: [BrowserShortcutCommand] = [
        .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4,
        .selectSpace5, .selectSpace6, .selectSpace7, .selectSpace8,
        .selectSpace9,
    ]
}
