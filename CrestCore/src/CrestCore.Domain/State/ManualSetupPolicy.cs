using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Rules for editing a manual-setup draft before the workspace import applies
/// it. The draft may add Spaces up to the import limit, add tabs within the
/// pinned limit, and follows the session when Spaces change elsewhere.
public static class ManualSetupPolicy {
    #region Variables

    public const string NewSpaceSymbol = "square.grid.2x2.fill";
    public const string PinnedTabSymbol = "pin.fill";
    public const string TabSymbol = "globe";
    public const int MaximumDrafts = WorkspaceImportPolicy.MaximumSpaces * 2;

    #endregion

    #region Actions - Spaces

    /// The ordinal of the Space a draft of <paramref name="draftCount"/> Spaces adds.
    public static int NewSpaceNumber(int draftCount) {
        if (draftCount < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidTabCount);
        if (draftCount >= WorkspaceImportPolicy.MaximumSpaces) throw new BrowserRuleException(BrowserRuleCodes.SpaceLimitReached);
        return draftCount + 1;
    }

    public static string NewSpaceName(int number) => $"Space {number}";

    /// Drops drafts of existing Spaces deleted elsewhere, refreshes the ones
    /// that remain, keeps every new draft in its place, and appends Spaces
    /// created elsewhere in session order.
    public static IReadOnlyList<ManualSetupEntry> Reconcile(IReadOnlyList<ManualSetupDraft> drafts, IReadOnlyList<Guid> existing) {
        ArgumentNullException.ThrowIfNull(drafts);
        ArgumentNullException.ThrowIfNull(existing);
        if (drafts.Count > MaximumDrafts || existing.Count > MaximumDrafts)
            throw new BrowserRuleException(BrowserRuleCodes.SpaceLimitReached);
        Dictionary<Guid, int> positions = [];
        for (int index = 0; index < existing.Count; index++) positions.TryAdd(existing[index], index);
        List<ManualSetupEntry> result = [];
        HashSet<Guid> claimed = [];
        for (int index = 0; index < drafts.Count; index++) {
            var draft = drafts[index];
            if (!draft.IsNew && !positions.ContainsKey(draft.Id)) continue;
            bool first = claimed.Add(draft.Id);
            result.Add(new(index, !draft.IsNew && first ? positions[draft.Id] : null));
        }
        for (int index = 0; index < existing.Count; index++)
            if (claimed.Add(existing[index])) result.Add(new(null, index));
        return result;
    }

    #endregion

    #region Actions - Tabs

    /// Admits a tab into a placement. <paramref name="otherAddedPinned"/>
    /// counts the draft's other pinned additions, excluding this tab.
    public static ManualSetupTab AdmitTab(TabPlacement placement, int existingPinned, int otherAddedPinned,
        string url, string? title) {
        ArgumentNullException.ThrowIfNull(url);
        if (existingPinned < 0 || otherAddedPinned < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidTabCount);
        if (placement == TabPlacement.Pinned && (long)existingPinned + otherAddedPinned >= WorkspaceImportPolicy.MaximumPinnedTabs)
            throw new BrowserRuleException(BrowserRuleCodes.PinnedLimitReached);
        return new(Title(url, title), placement == TabPlacement.Pinned ? PinnedTabSymbol : TabSymbol,
            placement != TabPlacement.Current);
    }

    /// The typed title when there is one, otherwise the site's host without a
    /// leading "www.", otherwise the address itself.
    public static string Title(string url, string? title) {
        ArgumentNullException.ThrowIfNull(url);
        if (!string.IsNullOrWhiteSpace(title)) return title.Trim();
        string host = Uri.TryCreate(url, UriKind.Absolute, out var parsed) && parsed.Host.Length > 0 ? parsed.Host : url;
        return SiteHost.WithoutWww(host);
    }

    #endregion
}
