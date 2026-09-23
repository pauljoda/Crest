namespace CrestCore.Domain;

/// Device-local window selection rules. A window references the session's
/// Space and tab identities; repair never invents a selection the person
/// deliberately cleared, and forgets column shares a group can no longer use.
public static class WindowStatePolicy {
    #region Variables

    public const int MaximumSpaces = WorkspaceImportPolicy.MaximumSpaces;
    public const int MaximumSplitLayouts = 64;

    /// How far captured shares may drift from summing to one before they are
    /// renormalized. Small enough that only rounding survives it.
    public const double FractionSumTolerance = 0.0001;

    #endregion

    #region Actions - Selection

    /// Repairs a window against the session it reflects. Selection is the
    /// window's own: a Space the window captured without a tab stays empty, and
    /// any other Space falls back to its first tab. A Space selection the
    /// session no longer has falls back to the first Space. A split layout
    /// survives only while its group renders with exactly as many members as it
    /// has columns. A window that records captured Spaces records every Space it
    /// has now reconciled; an older window records none.
    public static WindowRepair Repair(Guid selectedSpaceId, bool capturesSelection,
        IReadOnlyList<WindowSpaceFacts> spaces, IReadOnlyList<WindowSplitLayout> layouts) {
        ArgumentNullException.ThrowIfNull(spaces);
        ArgumentNullException.ThrowIfNull(layouts);
        if (spaces.Count > MaximumSpaces || layouts.Count > MaximumSplitLayouts)
            throw new BrowserRuleException(BrowserRuleCodes.WindowStateLimit);
        var ids = spaces.Select(space => space.Id).ToHashSet();
        if (ids.Count != spaces.Count) throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpace);
        if (layouts.Select(layout => layout.GroupId).Distinct().Count() != layouts.Count)
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSplit);
        var selected = ids.Contains(selectedSpaceId) ? selectedSpaceId
            : spaces.Count > 0 ? spaces[0].Id : selectedSpaceId;
        var kept = layouts.Where(layout => layout.LiveMembers == layout.Columns).Select(layout => layout.GroupId).ToArray();
        return new(selected, spaces.Select(Selection).ToArray(), kept,
            capturesSelection ? spaces.Select(space => space.Id).ToArray() : null);
    }

    private static WindowTabSelection Selection(WindowSpaceFacts space) {
        if (space.HasWindowTab) return WindowTabSelection.Window;
        if (space.IsCaptured) return WindowTabSelection.None;
        return space.HasTabs ? WindowTabSelection.First : WindowTabSelection.None;
    }

    #endregion

    #region Actions - Split layout

    /// The column shares to store for one group, or null when the list cannot
    /// describe columns: it must be non-empty, no longer than a group may be,
    /// and every entry a finite share greater than zero and at most the whole.
    /// A list that drifts from summing to one is normalized.
    public static IReadOnlyList<double>? SplitFractions(IReadOnlyList<double> fractions) {
        ArgumentNullException.ThrowIfNull(fractions);
        if (fractions.Count == 0 || fractions.Count > BrowserTabCollection.MaximumSplitMembers
            || fractions.Any(value => !double.IsFinite(value) || value <= 0 || value > 1)) return null;
        double total = fractions.Sum();
        if (!double.IsFinite(total) || total <= 0) return null;
        return Math.Abs(total - 1) <= FractionSumTolerance ? fractions.ToArray() : fractions.Select(value => value / total).ToArray();
    }

    #endregion

    #region Actions - Tear-off

    /// Whether a dragged tab may leave its window: its Space is still the one
    /// the drag started in, is unlocked and still holds the tab, and the drag
    /// carries that tab alone.
    public static bool AllowsTearOff(bool spaceMatches, bool spaceLocked, bool containsTab,
        int? selectionCount, bool selectionIncludesTab) =>
        spaceMatches && !spaceLocked && containsTab
        && (selectionCount is null || selectionCount == 1 && selectionIncludesTab);

    #endregion
}
