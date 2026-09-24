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

    /// The starting review for each imported Space, in their order. A
    /// disposable first-install seed offers no destinations, so everything
    /// imports into new Spaces.
    public static SuggestedImportReview Suggest(IReadOnlyList<ImportReviewSpace> sources,
        IReadOnlyList<ImportReviewSpace> existing, bool replacesDisposableSeed) {
        ArgumentNullException.ThrowIfNull(sources);
        ArgumentNullException.ThrowIfNull(existing);
        var destinations = replacesDisposableSeed ? [] : existing;
        return new([.. sources.Select(source => {
            string key = SpaceMatchKey(source.Name);
            var match = key.Length == 0 ? null : destinations.FirstOrDefault(space => SpaceMatchKey(space.Name) == key);
            var duplicates = match is null ? [] : Duplicates(source, match);
            var skipped = duplicates.ToHashSet();
            return new SuggestedSpaceReview(source.Id, match?.Id, duplicates,
                [.. source.Tabs.Where(tab => !skipped.Contains(tab.Id)).Select(tab => tab.Id)]);
        })]);
    }

    /// What the reviews mean for each of the imported Spaces, in their order.
    /// Each review names its Space; a destination that no longer exists holds
    /// no duplicates and no pinned tabs. Throws `Rejected` with `InvalidImport`
    /// when the reviews do not name each Space exactly once.
    public static AnalyzedImportReview Analyze(IReadOnlyList<ImportReviewSpace> sources,
        IReadOnlyList<ImportReviewSpace> existing, IReadOnlyList<SpaceReview> reviews) {
        ArgumentNullException.ThrowIfNull(sources);
        ArgumentNullException.ThrowIfNull(existing);
        ArgumentNullException.ThrowIfNull(reviews);
        var paired = Paired(sources, reviews, source => source.Id, review => review.SourceSpaceId);
        var byId = existing.GroupBy(space => space.Id).ToDictionary(group => group.Key, group => group.First());
        var spaces = new List<AnalyzedSpaceReview>();
        Dictionary<Guid, int> pinnedCounts = existing.GroupBy(space => space.Id)
            .ToDictionary(group => group.Key, group => group.First().Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        Dictionary<Guid, int> newCounts = [];
        List<Guid> overflow = [];
        foreach (var (source, review) in paired) {
            var destination = review.DestinationId is { } id ? byId.GetValueOrDefault(id) : null;
            spaces.Add(new(source.Id, destination is null ? [] : Duplicates(source, destination),
                destination is null || !review.Included ? [] : Matched(source, destination)));
            if (!review.Included) continue;
            var counts = review.DestinationId is null ? newCounts : pinnedCounts;
            var key = review.DestinationId ?? source.Id;
            var included = review.IncludedTabIds.ToHashSet();
            var placements = review.Placements.GroupBy(choice => choice.TabId)
                .ToDictionary(group => group.Key, group => group.Last().Placement);
            foreach (var tab in source.Tabs) {
                if (!included.Contains(tab.Id) || placements.GetValueOrDefault(tab.Id, tab.Placement) != TabPlacement.Pinned) continue;
                int count = counts.GetValueOrDefault(key);
                if (!TabPlacement.Pinned.Holds(count + 1)) overflow.Add(tab.Id);
                else counts[key] = count + 1;
            }
        }
        return new(spaces, overflow);
    }

    /// Each source with the one choice that names it, in the sources' order.
    /// Throws `Rejected` with `InvalidImport` unless the choices name each
    /// source exactly once and the sources' identities are distinct.
    public static IReadOnlyList<(TSource Source, TChoice Choice)> Paired<TSource, TChoice>(IReadOnlyList<TSource> sources,
        IReadOnlyList<TChoice> choices, Func<TSource, Guid> sourceId, Func<TChoice, Guid> choiceId) {
        var byId = new Dictionary<Guid, TChoice>();
        foreach (var choice in choices)
            if (!byId.TryAdd(choiceId(choice), choice)) throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices));
        if (sources.Select(sourceId).Distinct().Count() != sources.Count || byId.Count != sources.Count)
            throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices));
        return [.. sources.Select(source => byId.TryGetValue(sourceId(source), out var choice)
            ? (source, choice) : throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices)))];
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
