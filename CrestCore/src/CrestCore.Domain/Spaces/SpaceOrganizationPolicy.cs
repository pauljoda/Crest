using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Shared rules for Space commands, independent of native models and storage.
public static class SpaceOrganizationPolicy {
    #region Actions - Space organization

    public static IReadOnlyList<T> Move<T>(IReadOnlyList<T> values, IEnumerable<int> offsets, int destination) {
        var valid = offsets.Where(i => i >= 0 && i < values.Count).Distinct().Order().ToArray();
        var selected = valid.ToHashSet();
        var result = values.Where((_, i) => !selected.Contains(i)).ToList();
        var index = (int)Math.Clamp((long)destination - valid.Count(i => i < destination), 0, result.Count);
        result.InsertRange(index, valid.Select(i => values[i]));
        return result;
    }

    public static void RequireOwnedProfiles(WorkspaceKind kind) {
        if (kind == WorkspaceKind.Borrowed) throw new BrowserRuleException(BrowserRuleCodes.BorrowedProfile);
    }

    public static void RequireRemovable(int count) {
        if (count <= 1) throw new BrowserRuleException(BrowserRuleCodes.CannotDeleteLastSpace);
    }

    #endregion

    #region Mutators

    public static string Name(string value) => string.IsNullOrWhiteSpace(value) ? "Untitled Space" : value.Trim();

    public static string Symbol(string value) => string.IsNullOrWhiteSpace(value) ? "square.grid.2x2" : value.Trim();

    #endregion
}
