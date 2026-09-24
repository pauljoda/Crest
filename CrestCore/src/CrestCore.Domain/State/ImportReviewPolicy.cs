using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Rules for reviewing an import before the workspace import applies it. An
/// imported Space merges into the existing Space with the same name, tabs its
/// destination already holds are left out until the person asks for them, and
/// pinned tabs past a destination's limit are flagged.
public static class ImportReviewPolicy {
    #region Actions - Review

    /// The key two Space names match on: letters and digits only, ignoring
    /// case, accents and width. A name with neither never matches.
    public static string SpaceMatchKey(string name) => WorkspaceImportPolicy.FolderMatchKey(name);

    /// The key two tab addresses match on: the address a history visit would
    /// record, or the address itself when history would not record it.
    public static string UrlKey(string url) => new WebAddress(url).Normalized ?? url;

    /// The starting review for each imported Space. A disposable first-install
    /// seed offers no destinations, so everything imports into new Spaces.
    public static IReadOnlyList<ImportReviewSuggestion> Suggest(IReadOnlyList<ImportReviewSpace> sources,
        IReadOnlyList<ImportReviewSpace> existing, bool replacesDisposableSeed) {
        ArgumentNullException.ThrowIfNull(sources);
        ArgumentNullException.ThrowIfNull(existing);
        var destinations = replacesDisposableSeed ? [] : existing;
        return sources.Select(source => {
            string key = SpaceMatchKey(source.Name);
            var match = key.Length == 0 ? null : destinations.FirstOrDefault(space => SpaceMatchKey(space.Name) == key);
            var duplicates = match is null ? [] : Duplicates(source, match);
            var skipped = duplicates.ToHashSet();
            return new ImportReviewSuggestion(match?.Id, duplicates,
                source.Tabs.Where(tab => !skipped.Contains(tab.Id)).Select(tab => tab.Id).ToArray());
        }).ToArray();
    }

    /// What the current choices mean. <paramref name="choices"/> pairs with
    /// <paramref name="sources"/> by position; a destination that no longer
    /// exists holds no duplicates and no pinned tabs.
    public static ImportReviewAnalysis Analyze(IReadOnlyList<ImportReviewSpace> sources,
        IReadOnlyList<ImportReviewSpace> existing, IReadOnlyList<ImportReviewChoice> choices) {
        ArgumentNullException.ThrowIfNull(sources);
        ArgumentNullException.ThrowIfNull(existing);
        ArgumentNullException.ThrowIfNull(choices);
        if (choices.Count != sources.Count) throw new BrowserRuleException(BrowserRuleCodes.InvalidDestination);
        var byId = existing.GroupBy(space => space.Id).ToDictionary(group => group.Key, group => group.First());
        var duplicates = new List<IReadOnlyList<Guid>>();
        var matched = new List<IReadOnlyList<Guid>>();
        Dictionary<Guid, int> pinnedCounts = existing.GroupBy(space => space.Id)
            .ToDictionary(group => group.Key, group => group.First().Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        Dictionary<Guid, int> newCounts = [];
        List<Guid> overflow = [];
        for (int index = 0; index < sources.Count; index++) {
            var source = sources[index]; var choice = choices[index];
            var destination = choice.DestinationId is { } id ? byId.GetValueOrDefault(id) : null;
            duplicates.Add(destination is null ? [] : Duplicates(source, destination));
            matched.Add(destination is null || !choice.Included ? [] : Matched(source, destination));
            if (!choice.Included) continue;
            var counts = choice.DestinationId is null ? newCounts : pinnedCounts;
            var key = choice.DestinationId ?? source.Id;
            foreach (var tab in source.Tabs) {
                if (!choice.IncludedTabIds.Contains(tab.Id)
                    || choice.Placements.GetValueOrDefault(tab.Id, tab.Placement) != TabPlacement.Pinned) continue;
                int count = counts.GetValueOrDefault(key);
                if (!TabPlacement.Pinned.Holds(count + 1)) overflow.Add(tab.Id);
                else counts[key] = count + 1;
            }
        }
        return new(duplicates, matched, overflow);
    }

    private static HashSet<string> Keys(ImportReviewSpace space) =>
        space.Tabs.Where(tab => tab.Url is not null).Select(tab => UrlKey(tab.Url!)).ToHashSet(StringComparer.Ordinal);

    private static Guid[] Duplicates(ImportReviewSpace source, ImportReviewSpace destination) {
        var keys = Keys(destination);
        return source.Tabs.Where(tab => tab.Url is not null && keys.Contains(UrlKey(tab.Url))).Select(tab => tab.Id).ToArray();
    }

    private static Guid[] Matched(ImportReviewSpace source, ImportReviewSpace destination) {
        var keys = Keys(source);
        return destination.Tabs.Where(tab => tab.Url is not null && keys.Contains(UrlKey(tab.Url))).Select(tab => tab.Id).ToArray();
    }

    #endregion
}
