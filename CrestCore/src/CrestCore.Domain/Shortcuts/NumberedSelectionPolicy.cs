using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What the numbered selection commands reach: a command numbered N selects
/// the Nth tab in sidebar order, or the Nth Space, and is unavailable when
/// there are fewer than N.
public static class NumberedSelectionPolicy {
    #region Actions - Selection

    public static IReadOnlyList<NumberedSelection> Resolve(int tabCount, int spaceCount) {
        if (tabCount < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidTabCount);
        if (spaceCount < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidSpaceCount);
        var counts = new Dictionary<NumberedSelectionTarget, int> {
            [NumberedSelectionTarget.Tab] = tabCount,
            [NumberedSelectionTarget.Space] = spaceCount
        };
        return [.. ShortcutCommand.All.Where(command => command is { Selects: not null, Number: not null }).Select(command => {
            int index = command.Number!.Value - 1;
            return new NumberedSelection(command.Name, command.Selects!, index < counts[command.Selects!] ? index : null);
        })];
    }

    #endregion
}
