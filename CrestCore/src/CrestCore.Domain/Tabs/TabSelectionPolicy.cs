using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The tab a Space selects when its stored selection no longer exists: the
/// first open tab, then the first pinned tab, then the first tab at all.
public static class TabSelectionPolicy {
    #region Actions - Selection

    /// Index of the fallback within <paramref name="placements"/>, in Space
    /// order, or null for an empty Space. Callers may pass only the first tab
    /// of each placement; the answer is the same.
    public static int? Fallback(IReadOnlyList<TabPlacement> placements) {
        ArgumentNullException.ThrowIfNull(placements);
        if (placements.Count == 0) return null;
        for (int index = 0; index < placements.Count; index++)
            if (placements[index] == TabPlacement.Current) return index;
        for (int index = 0; index < placements.Count; index++)
            if (placements[index] == TabPlacement.Pinned) return index;
        return 0;
    }

    #endregion
}
