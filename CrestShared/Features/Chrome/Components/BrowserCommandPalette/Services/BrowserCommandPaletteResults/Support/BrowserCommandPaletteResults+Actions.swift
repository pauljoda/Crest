extension BrowserCommandPaletteResults {
    static func actionResults(
        query: BrowserCommandPaletteQuery,
        commands: [BrowserShortcutCommand]
    ) -> [BrowserCommandPaletteResult] {
        let available = commands.filter { !excludedCommands.contains($0) }
        guard !available.isEmpty else { return [] }
        guard !query.isEmpty else {
            let resting = restingCommands.filter(available.contains)
            return resting.prefix(BrowserCommandPaletteResultLimits.restingActions)
                .map(actionResult)
        }
        return rank(
            available,
            limit: BrowserCommandPaletteResultLimits.matchedActions
        ) { command in
            BrowserCommandPaletteText.score(
                query,
                title: command.title,
                detail: command.section.title
            )
        }
        .map(actionResult)
    }

    static func actionResult(
        _ command: BrowserShortcutCommand
    ) -> BrowserCommandPaletteResult {
        BrowserCommandPaletteResult(
            section: .actions,
            id: "command-\(command.rawValue)",
            title: command.title,
            subtitle: command.section.title,
            symbol: command.paletteSymbol,
            trailing: "",
            target: .command(command)
        )
    }
}
