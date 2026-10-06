using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Rules for reviewing an import before the workspace import applies it. An
/// imported Space joins the existing Space with the same name, tabs its
/// destination already holds are left out until the person asks for them,
/// pinned tabs past a destination's limit move to a saved folder, and no
/// choice brings more new Spaces than the workspace has room for. Each edit
/// answers the review as it leaves it, with what its choices mean against the
/// session worked out again.
public static class ImportReviewPolicy {
    #region Actions - Matching

    /// The key two Space names match on: letters and digits only, ignoring
    /// case, accents and width. A name with neither never matches.
    public static string SpaceMatchKey(string name) => WorkspaceImportPolicy.FolderMatchKey(name);

    /// The key two tab addresses match on: the address a history visit would
    /// record, or the address itself when history would not record it.
    public static string UrlKey(string url) => new WebAddress(url).Normalized ?? url;

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

    #endregion

    #region Actions - Starting

    /// The review a person starts from for the Spaces `source` brings, against
    /// `session`, looking at the first: each Space joins the existing Space of
    /// the same name, taking its name and look and leaving out the tabs it
    /// holds, or comes in as a new Space with its own. Each existing Space is
    /// joined by the first Space that matches it only, and a Space that would
    /// come in new once the workspace is full starts left out. A first
    /// launch's disposable Spaces are no destination, so everything comes in
    /// new in their place. `passwords` counts the saved passwords that belong
    /// with each Space, `extensions` lists the extensions each Space offers,
    /// all of them left on, and `leftOut` is what the read could not bring.
    public static SetupImportReview Started(ImportSource source, IReadOnlyList<SpaceState> spaces,
        IReadOnlyDictionary<Guid, int> passwords, IReadOnlyList<ImportSpaceExtensions> extensions, IReadOnlyList<ImportLeftOut> leftOut,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(spaces);
        ArgumentNullException.ThrowIfNull(passwords);
        ArgumentNullException.ThrowIfNull(extensions);
        ArgumentNullException.ThrowIfNull(leftOut);
        ArgumentNullException.ThrowIfNull(session);
        var destinations = Destinations(session);
        var offers = extensions.GroupBy(entry => entry.SpaceId).ToDictionary(group => group.Key,
            group => (IReadOnlyList<ImportExtension>)[.. group.SelectMany(entry => entry.Extensions)
                .DistinctBy(extension => extension.ExtensionId, StringComparer.Ordinal)]);
        int room = Room(session), created = 0;
        HashSet<Guid> joined = [];
        List<SetupReviewSpace> reviews = [];
        foreach (var space in spaces) {
            var offered = offers.GetValueOrDefault(space.Id) ?? [];
            string key = SpaceMatchKey(space.Settings.Name);
            var match = key.Length == 0 ? null
                : destinations.FirstOrDefault(existing => !joined.Contains(existing.Id) && SpaceMatchKey(existing.Settings.Name) == key);
            if (match is not null) joined.Add(match.Id);
            bool included = match is not null || created < room;
            if (included && match is null) created++;
            var duplicates = match is null ? [] : Duplicates(space, match).ToHashSet();
            reviews.Add(new SetupReviewSpace(space, included, match?.Id, Customization(match ?? space),
                included ? [.. space.Tabs.Where(tab => !duplicates.Contains(tab.Id)).Select(tab => tab.Id)] : [], [], [], [],
                IncludesPasswords: true, passwords.GetValueOrDefault(space.Id), offered, [.. offered.Select(extension => extension.ExtensionId)]));
        }
        return Analyzed(new SetupImportReview(source, reviews, [], spaces.FirstOrDefault()?.Id, leftOut, room), session);
    }

    /// The name and look `space` has, as a review offers them.
    private static SpaceCustomization Customization(SpaceState space) {
        var settings = space.Settings;
        return new(settings.Name, settings.Symbol, settings.Accent, settings.Look);
    }

    #endregion

    #region Actions - Editing

    /// `review` with `sourceId` joining the existing Space `destinationId` and
    /// taking its name and look, or coming in new with its own when null. A
    /// destination the session does not hold changes nothing.
    public static SetupImportReview ChoosingDestination(SetupImportReview review, Guid sourceId, Guid? destinationId, SessionState session) {
        ArgumentNullException.ThrowIfNull(session);
        var destination = destinationId is { } id ? Destinations(session).FirstOrDefault(space => space.Id == id) : null;
        if (destinationId is not null && destination is null) return review;
        return Editing(review, sourceId, session, space => space with {
            DestinationId = destination?.Id,
            Customization = Customization(destination ?? space.Source)
        });
    }

    /// `review` bringing the tabs `tabIds` of `sourceId`, and with them the
    /// Space, or leaving them out.
    public static SetupImportReview IncludingTabs(SetupImportReview review, Guid sourceId, IReadOnlyList<Guid> tabIds, bool included,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(tabIds);
        return Editing(review, sourceId, session, space => {
            var changed = space.Source.Tabs.Select(tab => tab.Id).Intersect(tabIds).ToHashSet();
            if (changed.Count == 0) return space;
            return included
                ? space with { Included = true, IncludedTabIds = Ordered(space, space.IncludedTabIds.Union(changed)) }
                : space with { IncludedTabIds = [.. space.IncludedTabIds.Where(tab => !changed.Contains(tab))] };
        });
    }

    /// `review` bringing the tab `tabId` of `sourceId` in `placement`, and
    /// with it the Space.
    public static SetupImportReview Placing(SetupImportReview review, Guid sourceId, Guid tabId, TabPlacement placement,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(placement);
        return Editing(review, sourceId, session, space => space.Source.Tabs.All(tab => tab.Id != tabId) ? space : space with {
            Included = true,
            IncludedTabIds = Ordered(space, space.IncludedTabIds.Append(tabId)),
            Placements = [.. space.Placements.Where(choice => choice.TabId != tabId), new TabPlacementChoice(tabId, placement)]
        });
    }

    /// `review` bringing `sourceId` with every tab its destination does not
    /// already hold, or leaving it out with all of them.
    public static SetupImportReview IncludingSpace(SetupImportReview review, Guid sourceId, bool included, SessionState session) =>
        Editing(review, sourceId, session, space => space with {
            Included = included,
            IncludedTabIds = included ? [.. space.Source.Tabs.Select(tab => tab.Id).Except(space.DuplicateTabIds)] : []
        });

    /// `review` bringing the saved passwords of `sourceId`, or leaving them out.
    public static SetupImportReview IncludingPasswords(SetupImportReview review, Guid sourceId, bool included, SessionState session) =>
        Editing(review, sourceId, session, space => space with { IncludesPasswords = included });

    /// `review` installing the extension `extensionId` that `sourceId` offers,
    /// or leaving it out. An extension the Space does not offer changes nothing.
    public static SetupImportReview IncludingExtension(SetupImportReview review, Guid sourceId, string extensionId, bool included,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(extensionId);
        return Editing(review, sourceId, session, space => {
            if (space.Extensions.All(extension => extension.ExtensionId != extensionId)) return space;
            var kept = space.IncludedExtensionIds.Where(id => id != extensionId);
            return space with { IncludedExtensionIds = [.. included ? kept.Append(extensionId) : kept] };
        });
    }

    /// `review` with `sourceId` taking the name and look of `customization`,
    /// its look kept within the ranges every device draws.
    public static SetupImportReview Customizing(SetupImportReview review, Guid sourceId, SpaceCustomization customization,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(customization);
        var kept = customization with { Branding = SpaceBrandingPolicy.Normalize(customization.Branding) };
        return Editing(review, sourceId, session, space => space with { Customization = kept });
    }

    /// `review` looking at `sourceId`, when it holds it.
    public static SetupImportReview Showing(SetupImportReview review, Guid sourceId) {
        ArgumentNullException.ThrowIfNull(review);
        return review.Spaces.Any(space => space.Source.Id == sourceId) ? review with { ShownSpaceId = sourceId } : review;
    }

    /// `review` with `edit` made to `sourceId`, unless it would bring the
    /// Space in new once the workspace is full, which changes nothing.
    private static SetupImportReview Editing(SetupImportReview review, Guid sourceId, SessionState session,
        Func<SetupReviewSpace, SetupReviewSpace> edit) {
        ArgumentNullException.ThrowIfNull(review);
        ArgumentNullException.ThrowIfNull(session);
        if (review.Spaces.FirstOrDefault(space => space.Source.Id == sourceId) is not { } current) return review;
        var edited = edit(current);
        if (edited.MakesNewSpace && !current.MakesNewSpace && review.Spaces.Count(space => space.MakesNewSpace) >= Room(session))
            return review;
        return Analyzed(review with {
            Spaces = [.. review.Spaces.Select(space => space.Source.Id == sourceId ? edited : space)]
        }, session);
    }

    /// `ids` in the order the Space holds its tabs.
    private static Guid[] Ordered(SetupReviewSpace space, IEnumerable<Guid> ids) {
        var chosen = ids.ToHashSet();
        return [.. space.Source.Tabs.Select(tab => tab.Id).Where(chosen.Contains)];
    }

    #endregion

    #region Actions - Analysis

    /// `review` with what its choices mean against `session`: each Space's
    /// tabs its destination already holds and the destination's tabs it
    /// matches, the pinned tabs past each destination's limit, and the room
    /// the workspace has for new Spaces.
    public static SetupImportReview Analyzed(SetupImportReview review, SessionState session) {
        ArgumentNullException.ThrowIfNull(review);
        ArgumentNullException.ThrowIfNull(session);
        var byId = Destinations(session).ToDictionary(space => space.Id);
        var pinned = byId.ToDictionary(entry => entry.Key, entry => entry.Value.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        Dictionary<Guid, int> created = [];
        List<Guid> overflow = [];
        var spaces = review.Spaces.Select(space => {
            var destination = space.DestinationId is { } id ? byId.GetValueOrDefault(id) : null;
            var analyzed = space with {
                DuplicateTabIds = destination is null ? [] : Duplicates(space.Source, destination),
                MatchedTabIds = destination is null || !space.Included ? [] : Matched(space.Source, destination)
            };
            if (!space.Included) return analyzed;
            var counts = space.DestinationId is null ? created : pinned;
            var key = space.DestinationId ?? space.Source.Id;
            var included = space.IncludedTabIds.ToHashSet();
            var placements = space.Placements.GroupBy(choice => choice.TabId).ToDictionary(group => group.Key, group => group.Last().Placement);
            foreach (var tab in space.Source.Tabs) {
                if (!included.Contains(tab.Id) || placements.GetValueOrDefault(tab.Id, tab.Placement) != TabPlacement.Pinned) continue;
                int count = counts.GetValueOrDefault(key);
                if (!TabPlacement.Pinned.Holds(count + 1)) overflow.Add(tab.Id);
                else counts[key] = count + 1;
            }
            return analyzed;
        }).ToArray();
        return review with { Spaces = spaces, OverflowTabIds = overflow, SpaceRoom = Room(session) };
    }

    /// How many new Spaces an import into `session` has room for, as
    /// `ImportReviewedSpaces` counts them: a first launch's disposable Spaces
    /// make way for the import, and every other Space counts.
    private static int Room(SessionState session) =>
        Math.Max(0, WorkspaceImportPolicy.MaximumSpaces - (session.DisposableSeedMarker is null ? session.Spaces.Count : 0));

    /// The Spaces an import may join: none over a first launch's disposable
    /// Spaces, and never one going away.
    private static IReadOnlyList<SpaceState> Destinations(SessionState session) => session.DisposableSeedMarker is not null ? []
        : [.. session.Spaces.Where(space => session.SpaceDeletions.All(deletion => deletion.SpaceId != space.Id))];

    private static HashSet<string> Keys(SpaceState space) =>
        space.Tabs.Where(tab => tab.Url is not null).Select(tab => UrlKey(tab.Url!)).ToHashSet(StringComparer.Ordinal);

    private static Guid[] Duplicates(SpaceState source, SpaceState destination) {
        var keys = Keys(destination);
        return [.. source.Tabs.Where(tab => tab.Url is not null && keys.Contains(UrlKey(tab.Url))).Select(tab => tab.Id)];
    }

    private static Guid[] Matched(SpaceState source, SpaceState destination) {
        var keys = Keys(source);
        return [.. destination.Tabs.Where(tab => tab.Url is not null && keys.Contains(UrlKey(tab.Url))).Select(tab => tab.Id)];
    }

    #endregion
}
