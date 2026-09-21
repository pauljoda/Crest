namespace CrestCore.Domain;

/// Which pages memory pressure may take back, and how many of them.
///
/// The ordering and eligibility answered here must be identical on every
/// engine. The native adapter still owns the per-page veto: a page playing or
/// capturing media, holding Picture in Picture, or whose media state is unknown
/// stays resident whatever this policy proposes.
public static class PageResidencyPolicy {
    #region Variables

    /// How far from the focused card a presented member must sit before critical
    /// pressure may reclaim it. The focused card and both neighbours are one
    /// swipe away, so evicting them would trade a background page for a blank.
    public const int ProtectedNeighbourDistance = 1;

    public const int MaximumCandidates = 256;

    #endregion

    #region Actions - Lifecycle

    public static int ReleaseLimit(MemoryPressureLevel level, int eligiblePageCount, MemoryPressurePlatform platform) {
        if (eligiblePageCount < 0) throw new BrowserRuleException("invalid_page_count");
        if (eligiblePageCount == 0) return 0;
        return (platform, level) switch {
            (MemoryPressurePlatform.Desktop, MemoryPressureLevel.Warning) => 1,
            (MemoryPressurePlatform.Desktop, MemoryPressureLevel.Critical) => Math.Max(1, (eligiblePageCount + 1) / 2),
            (MemoryPressurePlatform.Mobile, MemoryPressureLevel.Warning) => 0,
            _ => 1
        };
    }

    /// The release attempt order: every off-screen candidate the person has not
    /// asked to keep loaded, least recently used first, ties broken on tab
    /// identity so a squeeze is deterministic.
    ///
    /// `PresentedFallback` answers nothing unless pressure is critical on a
    /// carousel platform. It is only for the case where the off-screen sweep
    /// releases nobody at all: a store with nothing to give hands the system a
    /// termination instead of a reclaim, which costs every card rather than one.
    public static (IReadOnlyList<string> OffScreen, IReadOnlyList<string> PresentedFallback) ReleasePlan(
        IReadOnlyList<ResidencyCandidate> candidates, MemoryPressureLevel level,
        MemoryPressurePlatform platform, int? focusedIndex) {
        if (candidates.Count > MaximumCandidates) throw new BrowserRuleException("residency_candidate_limit");
        if (candidates.Select(candidate => candidate.TabId).Distinct(StringComparer.Ordinal).Count() != candidates.Count)
            throw new BrowserRuleException("duplicate_residency_candidate");
        foreach (var candidate in candidates) {
            if (candidate.InactiveSince is { } stamp && !double.IsFinite(stamp))
                throw new BrowserRuleException("invalid_residency_stamp");
            if (candidate.IsPresented != candidate.PresentedIndex.HasValue || candidate.PresentedIndex < 0)
                throw new BrowserRuleException("invalid_presented_candidate");
        }
        if (focusedIndex < 0) throw new BrowserRuleException("invalid_focused_index");
        var offScreen = Ordered(candidates.Where(candidate => !candidate.IsPresented && !candidate.KeepsPageLoaded));
        var fallback = level == MemoryPressureLevel.Critical && platform == MemoryPressurePlatform.Mobile
            && focusedIndex is { } focus
            ? Ordered(candidates.Where(candidate => candidate.IsPresented && !candidate.KeepsPageLoaded
                && Math.Abs(candidate.PresentedIndex!.Value - focus) > ProtectedNeighbourDistance))
            : [];
        return (offScreen, fallback);
    }

    private static IReadOnlyList<string> Ordered(IEnumerable<ResidencyCandidate> candidates) => candidates
        .OrderBy(candidate => candidate.InactiveSince.HasValue ? 0 : 1)
        .ThenBy(candidate => candidate.InactiveSince ?? 0)
        .ThenBy(candidate => candidate.TabId, StringComparer.Ordinal)
        .Select(candidate => candidate.TabId)
        .ToArray();

    #endregion
}
