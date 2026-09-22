namespace CrestCore.Domain;

/// What the numbered selection commands reach: the Nth command of a family
/// selects the Nth tab in sidebar order, or the Nth Space, and is unavailable
/// when there are fewer than N.
public static class NumberedSelectionPolicy {
    #region Actions - Selection

    public static IReadOnlyList<NumberedSelection> Resolve(int tabCount, int spaceCount) {
        if (tabCount < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidTabCount);
        if (spaceCount < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidSpaceCount);
        return Family(ShortcutCatalog.TabSelectionCommands, NumberedSelectionTarget.Tab, tabCount)
            .Concat(Family(ShortcutCatalog.SpaceSelectionCommands, NumberedSelectionTarget.Space, spaceCount))
            .ToArray();
    }

    private static IEnumerable<NumberedSelection> Family(IReadOnlyList<string> commands, NumberedSelectionTarget target,
        int count) => commands.Select((command, index) => new NumberedSelection(command, target, index < count ? index : null));

    #endregion
}
