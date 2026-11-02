using CrestCore.Domain;

namespace CrestCore.Contracts;

/// <summary>
/// The browsing session: its Spaces in order, the Space a launch opens, the marker of
/// a disposable first-install seed, Space deletions under way on this device and the
/// app-wide preferences. What each window shows is window state and never part of it.
/// <see cref="AppPreferences"/> is null until the settings kept before the core owned
/// them are imported.
/// </summary>
public sealed record SessionState(
    IReadOnlyList<SpaceState> Spaces,
    Guid? DefaultSpaceId,
    Guid? DisposableSeedMarker,
    IReadOnlyList<SpaceDeletionState> SpaceDeletions,
    AppPreferences? AppPreferences) {
    #region Static Variables

    /// The most Spaces a session holds.
    internal const int MaximumSpaces = 64;

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SpaceState> Spaces {
        get;
        init => field = [.. value];
    } = [.. Spaces];

    public IReadOnlyList<SpaceDeletionState> SpaceDeletions {
        get;
        init => field = [.. value];
    } = [.. SpaceDeletions];

    #endregion

    #region Actions - Spaces

    /// The Spaces of the session that are not going away.
    internal IReadOnlyList<SpaceState> StayingSpaces => [.. Spaces.Where(space => PendingDeletion(space.Id) is null)];

    /// The Space `id` names, or null when the session holds none.
    internal SpaceState? Space(Guid id) => Spaces.FirstOrDefault(space => space.Id == id);

    /// The Space `id` names. Throws `Rejected` with `UnknownSpace` when the
    /// session holds none.
    internal SpaceState KnownSpace(Guid id) => Space(id) ?? throw new Rejected(new UnknownSpace(id));

    /// The deletion under way of the Space `spaceId` names, or null while it stays.
    internal SpaceDeletionState? PendingDeletion(Guid spaceId) =>
        SpaceDeletions.FirstOrDefault(deletion => deletion.SpaceId == spaceId);

    /// The deletion of `space` under `operationId`: it erases the Space's own
    /// profile and the one it browses with, but none that a Space staying
    /// after it and the Spaces `alsoLeaving` names browses with.
    internal SpaceDeletionState Deleting(SpaceState space, Guid operationId, IReadOnlySet<Guid>? alsoLeaving = null) {
        var kept = StayingSpaces.Where(other => other.Id != space.Id && alsoLeaving?.Contains(other.Id) != true)
            .Select(other => other.ProfileId).ToHashSet();
        return new(operationId, space.Id, space.OwnProfileId,
            [.. new[] { space.OwnProfileId, space.ProfileId }.Distinct().Where(profile => !kept.Contains(profile))]);
    }

    /// The groups of the Spaces, in order; see `SpaceGroup`.
    internal IReadOnlyList<SpaceGroup> Groups => SpaceGroup.Of(Spaces, SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet());

    /// The session with `edited` in place of its Space, and `setting` copied
    /// from it to every other Space of its group; see `GroupSetting`.
    internal SessionState Sharing(SpaceState edited, GroupSetting setting) {
        var others = GroupOf(edited.Id)?.Members.Where(member => member.Id != edited.Id && PendingDeletion(member.Id) is null) ?? [];
        return Replacing([edited, .. others.Select(member => member.Configured(setting.Copied(edited.Settings, member.Settings)))]);
    }

    /// Whether the Space `spaceId` names leads a Sub-Space that stays.
    internal bool Leads(Guid spaceId) => Spaces.Any(space => space.PrimaryId == spaceId && PendingDeletion(space.Id) is null);

    /// `name` with the next number no Space's name wears: "Work" and "Work 2"
    /// both give "Work 2" while no Space is named that, else "Work 3", and on.
    internal string NextName(string name) {
        var trimmed = name.TrimEnd();
        var space = trimmed.LastIndexOf(' ');
        var stem = space > 0 && int.TryParse(trimmed.AsSpan(space + 1), out _) ? trimmed[..space] : trimmed;
        var taken = Spaces.Select(candidate => candidate.Settings.Name.Trim()).ToHashSet(StringComparer.CurrentCultureIgnoreCase);
        var number = 2;
        while (taken.Contains($"{stem} {number}")) number++;
        return $"{stem} {number}";
    }

    /// The session once `successor` takes `group` over from its primary at
    /// `now`, as the primary's deletion begins; see `SpaceGroup.HandedTo`. The
    /// group then sits where its new primary does.
    internal SessionState HandingOver(SpaceGroup group, SpaceState successor, DateTimeOffset now) {
        var handed = Replacing([.. group.HandedTo(successor, now)]);
        HashSet<Guid> pending = [.. SpaceDeletions.Select(deletion => deletion.SpaceId), group.Primary.Id];
        return handed with { Spaces = SpaceGroup.Regrouped(handed.Spaces, pending) };
    }

    /// The group that holds the Space `spaceId` names, or null when none does.
    internal SpaceGroup? GroupOf(Guid spaceId) => Groups.FirstOrDefault(group => group.Members.Any(member => member.Id == spaceId));

    /// The session with each of `edited` in place of the Space of its id; the
    /// first of `edited` for an id wins. A Space as its sidebar shows it (see
    /// `Viewed`) goes back to being stored: its own hidden pinned tabs stay as
    /// they were, and when its pinned tabs changed, they replace those of the
    /// Space it showed them from.
    internal SessionState Replacing(params SpaceState[] edited) {
        var values = new Dictionary<Guid, SpaceState>();
        foreach (var value in edited.Where(value => value.ViewsPinsOf is null)) values.TryAdd(value.Id, value);
        foreach (var view in edited.Where(value => value.ViewsPinsOf is not null)) {
            if (values.ContainsKey(view.Id) || Space(view.Id) is not { } stored || Space(view.ViewsPinsOf!.Value) is not { } owner) continue;
            List<TabState> pins = [.. view.Tabs.Where(tab => tab.IsPinned)], others = [.. view.Tabs.Where(tab => !tab.IsPinned)];
            values[view.Id] = view with {
                Tabs = others.SequenceEqual(stored.Tabs.Where(tab => !tab.IsPinned)) ? stored.Tabs
                    : [.. stored.Tabs.Where(tab => tab.IsPinned), .. others],
                ViewsPinsOf = null
            };
            if (pins.SequenceEqual(owner.Tabs.Where(tab => tab.IsPinned))) continue;
            var pinned = values.GetValueOrDefault(owner.Id) ?? owner;
            values[owner.Id] = pinned with { Tabs = [.. pins, .. pinned.Tabs.Where(tab => !tab.IsPinned)] };
        }
        return this with { Spaces = [.. Spaces.Select(space => values.GetValueOrDefault(space.Id) ?? space)] };
    }

    /// `space` as its sidebar shows it: with the pinned tabs of the Space whose
    /// pins it shows in place of its own, which stay stored in it, hidden; see
    /// `SpaceState.PinOwnerId`. Every rule that finds a tab of a Space a window
    /// shows reads it this way, so a pin shared by a group is one tab whichever
    /// Sub-Space shows it, and an edit made through it, once `Replacing` takes
    /// it, stores the group's pins in their owner. A Space that shows its own
    /// pins is itself.
    internal SpaceState Viewed(SpaceState space) {
        if (space.ViewsPinsOf is not null || space.PinOwnerId is not { } ownerId || ownerId == space.Id
            || Space(ownerId) is not { } owner) return space;
        return space with { Tabs = [.. owner.Tabs.Where(tab => tab.IsPinned), .. space.Tabs.Where(tab => !tab.IsPinned)], ViewsPinsOf = owner.Id };
    }

    /// The Space `id` names as its sidebar shows it (see `Viewed`), or null
    /// when the session holds none.
    internal SpaceState? ViewedSpace(Guid id) => Space(id) is { } space ? Viewed(space) : null;

    /// The Space that keeps what `space` records, such as the visits its pages
    /// make: the primary of its group, which owns the group's records, or the
    /// Space itself.
    internal SpaceState RecordsOwner(SpaceState space) =>
        space.PrimaryId is { } primaryId && Space(primaryId) is { } primary && PendingDeletion(primaryId) is null ? primary : space;

    /// The history the group of `space` holds, newest visit first: what its
    /// primary records for the group, and what each member held before it
    /// joined. A Space on its own holds its own.
    internal IReadOnlyList<HistoryEntryState> GroupHistory(SpaceState space) {
        if (GroupOf(space.Id) is not { SubSpaces.Count: > 0 } group) return space.History;
        return [.. group.Members.Where(member => PendingDeletion(member.Id) is null).SelectMany(member => member.History)
            .OrderByDescending(entry => entry.LastVisitedAt)];
    }

    /// `space` as a search over it reads it: as its sidebar shows it, with the
    /// history of its whole group. Never stored.
    internal SpaceState Searched(SpaceState space) => Viewed(space) with { History = GroupHistory(space) };

    /// The Spaces an import may join: none over a first launch's disposable
    /// Spaces, and never one going away.
    internal IReadOnlyList<SpaceState> ImportDestinations => DisposableSeedMarker is not null ? [] : StayingSpaces;

    /// How many new Spaces an import into the session has room for, as
    /// `ImportReviewedSpaces` counts them: a first launch's disposable Spaces
    /// make way for the import, and every other Space counts.
    internal int ImportRoom => Math.Max(0, MaximumSpaces - (DisposableSeedMarker is null ? Spaces.Count : 0));

    /// Throws `Rejected` with `SpaceLimitReached` when `additions` more Spaces
    /// would take a workspace holding `existing` past the limit.
    internal static void RequireSpaceCapacity(int existing, int additions) {
        if ((long)existing + additions > MaximumSpaces) throw new Rejected(new SpaceLimitReached(MaximumSpaces));
    }

    /// Throws `Rejected` with `CannotDeleteLastSpace` unless `spaceCount`
    /// Spaces leave one behind when one goes.
    internal static void RequireRemovable(int spaceCount) {
        if (spaceCount <= 1) throw new Rejected(new CannotDeleteLastSpace());
    }

    #endregion

    #region Actions - Equality

    public bool Equals(SessionState? other) => ReferenceEquals(this, other) || other is not null
        && Spaces.SequenceEqual(other.Spaces)
        && DefaultSpaceId == other.DefaultSpaceId
        && DisposableSeedMarker == other.DisposableSeedMarker
        && SpaceDeletions.SequenceEqual(other.SpaceDeletions)
        && AppPreferences == other.AppPreferences;

    public override int GetHashCode() => HashCode.Combine(Spaces.Count, DefaultSpaceId, DisposableSeedMarker, SpaceDeletions.Count);

    #endregion
}
