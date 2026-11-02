using CrestCore.Contracts;

namespace CrestCore.Domain;

/// <summary>
/// A primary Space and the Sub-Spaces that joined its session, in order. Every member
/// browses with the primary's profile, and they sit together: the primary, then its
/// Sub-Spaces. A Space on its own is a group of one, and no two groups browse with one
/// profile.
/// </summary>
/// <remarks>
/// Only Spaces that stay count. A Sub-Space whose deletion is under way belongs to no
/// group and is left as it is; a primary whose deletion is under way still leads the
/// Sub-Spaces that stay until it is removed, and leads nothing once none stays.
/// </remarks>
internal sealed record SpaceGroup(SpaceState Primary, IReadOnlyList<SpaceState> SubSpaces) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SpaceState> SubSpaces {
        get;
        init => field = [.. value];
    } = [.. SubSpaces];

    /// The primary, then its Sub-Spaces.
    public IReadOnlyList<SpaceState> Members => [Primary, .. SubSpaces];

    /// The profile every member browses with.
    public Guid ProfileId => Primary.ProfileId;

    /// The member a person used last: the one whose tab was shown most recently.
    public SpaceState LastUsed => Members.MaxBy(member => member.LastShownAt)!;

    #endregion

    #region Actions - Reading

    /// The groups `spaces` holds, in order, where `pending` names the Spaces
    /// whose deletion is under way. Each group sits where its primary does.
    internal static IReadOnlyList<SpaceGroup> Of(IReadOnlyList<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var led = Led(spaces, pending);
        return [.. spaces.Where(space => space.PrimaryId is null && (!pending.Contains(space.Id) || led.ContainsKey(space.Id)))
            .Select(primary => new SpaceGroup(primary, led.GetValueOrDefault(primary.Id) ?? []))];
    }

    #endregion

    #region Actions - Rules

    /// The first rule the Spaces' groups break, in session order, or null when
    /// they break none: every Sub-Space that stays names a primary the session
    /// holds, sits in its primary's group and browses with its profile, and no
    /// two groups browse with one profile.
    internal static SessionFlaw? Flaw(IReadOnlyList<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var byId = spaces.DistinctBy(space => space.Id).ToDictionary(space => space.Id);
        Guid? leading = null;
        var profiles = new HashSet<Guid>();
        foreach (var space in spaces) {
            if (space.PrimaryId is not { } primaryId) {
                if (pending.Contains(space.Id) && !Leads(space, spaces, pending)) continue;
                leading = space.Id;
                if (!profiles.Add(space.ProfileId)) return SessionFlaw.SharedProfile;
                continue;
            }
            if (pending.Contains(space.Id)) continue;
            if (!byId.TryGetValue(primaryId, out var primary) || primary.Id == space.Id || primary.PrimaryId is not null)
                return SessionFlaw.UnknownPrimary;
            if (leading != primaryId || space.ProfileId != primary.ProfileId) return SessionFlaw.ScatteredGroup;
        }
        return null;
    }

    #endregion

    #region Actions - Succession

    /// The group's members once `successor`, one of its Sub-Spaces, takes the
    /// group over at `now` from its primary, whose deletion begins: the
    /// successor leads the group with its session, every other Sub-Space joins
    /// it, and what the primary kept for the group moves to it. The primary's
    /// history is made again there, since a history record never changes
    /// Space, merged with the successor's own, newest first and up to the most
    /// a history keeps; each entry made again takes an identity drawn from the
    /// successor's and its own, so every device that hands the group over
    /// makes the same records. While the group shares pinned tabs, the
    /// primary's pins move there ahead of the successor's own, up to the most a
    /// Space pins, and the rest become its saved tabs.
    internal IReadOnlyList<SpaceState> HandedTo(SpaceState successor, DateTimeOffset now) {
        var primary = Primary;
        var leading = successor with {
            Membership = SpaceMembership.Leading(ProfileId, now),
            History = Merged(primary.History, successor.History, entry => Derived(successor.Id, entry.Id))
        };
        if (!primary.Settings.SeparatesPinnedTabs) {
            List<TabState> pins = [.. primary.Tabs.Where(tab => tab.IsPinned), .. successor.Tabs.Where(tab => tab.IsPinned)];
            leading = leading with {
                Tabs = [.. pins.Take(TabPlacement.PinnedCapacity),
                    .. pins.Skip(TabPlacement.PinnedCapacity).Select(tab => tab with { Placement = TabPlacement.Pinned.OverflowsTo! }),
                    .. successor.Tabs.Where(tab => !tab.IsPinned)]
            };
            primary = primary with { Tabs = [.. primary.Tabs.Where(tab => !tab.IsPinned)] };
        }
        return [primary, leading, .. SubSpaces.Where(member => member.Id != successor.Id)
            .Select(member => member with { Membership = SpaceMembership.Joining(leading, now) })];
    }

    /// `kept` with the entries of `moved` made again in it, one entry per
    /// address, newest first and up to the most a history keeps: an address
    /// both hold keeps `kept`'s identity with the visits of both.
    private static IReadOnlyList<HistoryEntryState> Merged(IReadOnlyList<HistoryEntryState> moved, IReadOnlyList<HistoryEntryState> kept,
        Func<HistoryEntryState, Guid> identity) {
        var byUrl = kept.DistinctBy(entry => entry.Url).ToDictionary(entry => entry.Url);
        foreach (var entry in moved) {
            byUrl[entry.Url] = byUrl.TryGetValue(entry.Url, out var existing)
                ? existing with {
                    Title = entry.LastVisitedAt > existing.LastVisitedAt ? entry.Title : existing.Title,
                    FirstVisitedAt = entry.FirstVisitedAt < existing.FirstVisitedAt ? entry.FirstVisitedAt : existing.FirstVisitedAt,
                    LastVisitedAt = entry.LastVisitedAt > existing.LastVisitedAt ? entry.LastVisitedAt : existing.LastVisitedAt,
                    VisitCount = existing.VisitCount + entry.VisitCount
                }
                : entry with { Id = identity(entry) };
        }
        return [.. byUrl.Values.OrderByDescending(entry => entry.LastVisitedAt).Take(HistoryEntryState.MaximumEntries)];
    }

    /// The identity `space` gives what it makes again of `source`: the same
    /// on every device, and unlike any other.
    private static Guid Derived(Guid space, Guid source) {
        Span<byte> input = stackalloc byte[32];
        space.TryWriteBytes(input[..16]);
        source.TryWriteBytes(input[16..]);
        Span<byte> hash = stackalloc byte[32];
        System.Security.Cryptography.SHA256.HashData(input, hash);
        // A version 8 identity, of the RFC 4122 variant.
        hash[7] = (byte)((hash[7] & 0x0F) | 0x80);
        hash[8] = (byte)((hash[8] & 0x3F) | 0x80);
        return new Guid(hash[..16]);
    }

    #endregion

    #region Actions - Repair

    /// `spaces` with every group mended, where `pending` names the Spaces
    /// whose deletion is under way, which stay exactly as they are. A Sub-Space
    /// whose primary is a Sub-Space itself joins that one's primary. The
    /// Sub-Spaces of a primary that is gone stay together, led by the first of
    /// them, which keeps their profile. A Sub-Space browses with its primary's
    /// profile. A group that took over a profile another group browses with
    /// gives it up and browses with its primary's own. Each group sits where
    /// its primary does, and its members' shared settings are settled; see
    /// `GroupSetting`. A Space that needs no mending is the same object.
    internal static IReadOnlyList<SpaceState> Regrouped(IReadOnlyList<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var mended = Mended(spaces, pending);
        mended = Distinct(mended, pending);
        mended = Aligned(mended, pending);
        return Settled(Gathered(mended, pending), pending);
    }

    /// Every group's members that stay share its settings.
    private static IReadOnlyList<SpaceState> Settled(IReadOnlyList<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var settled = Of(spaces, pending).Where(group => group.SubSpaces.Count > 0)
            .SelectMany(group => GroupSetting.Settled([.. group.Members.Where(member => !pending.Contains(member.Id))]))
            .ToDictionary(member => member.Id);
        if (settled.Count == 0) return spaces;
        List<SpaceState> result = [.. spaces.Select(space => settled.GetValueOrDefault(space.Id) ?? space)];
        return result.Select((space, index) => ReferenceEquals(space, spaces[index])).All(same => same) ? spaces : result;
    }

    /// Every Sub-Space that stays names a primary the session holds, once:
    /// one whose primary is a Sub-Space joins that one's primary, and those
    /// whose primary is gone are led by the first of them.
    private static List<SpaceState> Mended(IReadOnlyList<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var byId = spaces.DistinctBy(space => space.Id).ToDictionary(space => space.Id);
        var result = spaces.ToList();
        var orphans = new Dictionary<Guid, List<int>>();
        for (var index = 0; index < result.Count; index++) {
            var space = result[index];
            if (pending.Contains(space.Id) || space.PrimaryId is not { } primaryId) continue;
            if (PrimaryOf(byId, space, primaryId) is { } primary) {
                if (primary.Id != primaryId) result[index] = space with { Membership = space.Membership! with { PrimaryId = primary.Id } };
                continue;
            }
            if (!orphans.TryGetValue(primaryId, out var members)) orphans[primaryId] = members = [];
            members.Add(index);
        }
        foreach (var members in orphans.Values) {
            var modifiedAt = members.Max(index => result[index].Membership!.ModifiedAt);
            var leader = result[members[0]];
            result[members[0]] = leader with {
                Membership = leader.Membership!.SharedProfileId is { } profile
                    ? SpaceMembership.Leading(profile, modifiedAt) : SpaceMembership.Leaving(modifiedAt)
            };
            foreach (var index in members.Skip(1))
                result[index] = result[index] with { Membership = SpaceMembership.Joining(result[members[0]], modifiedAt) };
        }
        return result;
    }

    /// The primary `space` joins when it names `primaryId`: that Space when it
    /// is a primary, its primary when it is a Sub-Space of one, or null when
    /// neither stays in the session.
    private static SpaceState? PrimaryOf(Dictionary<Guid, SpaceState> byId, SpaceState space, Guid primaryId) {
        if (!byId.TryGetValue(primaryId, out var named) || named.Id == space.Id) return null;
        if (named.PrimaryId is null) return named;
        return named.PrimaryId is { } next && next != space.Id && byId.TryGetValue(next, out var primary) && primary.PrimaryId is null
            ? primary : null;
    }

    /// No two groups browse with one profile: a primary that browses with its
    /// own profile keeps it, and of two primaries that took one over, the
    /// first keeps it while the other browses with its own again.
    private static List<SpaceState> Distinct(List<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var primaries = spaces.Where(space => space.PrimaryId is null && (!pending.Contains(space.Id) || Leads(space, spaces, pending)))
            .ToList();
        var taken = primaries.Where(primary => primary.Membership?.SharedProfileId is null).Select(primary => primary.ProfileId)
            .ToHashSet();
        var result = spaces.ToList();
        foreach (var primary in primaries.Where(primary => primary.Membership?.SharedProfileId is not null)) {
            if (taken.Add(primary.ProfileId)) continue;
            var index = result.IndexOf(primary);
            result[index] = primary with { Membership = SpaceMembership.Leaving(primary.Membership!.ModifiedAt) };
        }
        return result;
    }

    /// Every Sub-Space that stays browses with its primary's profile.
    private static List<SpaceState> Aligned(List<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var byId = spaces.DistinctBy(space => space.Id).ToDictionary(space => space.Id);
        return [.. spaces.Select(space => !pending.Contains(space.Id) && space.PrimaryId is { } primaryId
            && byId[primaryId].ProfileId is var profile && space.ProfileId != profile
                ? space with { Membership = space.Membership! with { SharedProfileId = profile } } : space)];
    }

    /// Each group's Sub-Spaces follow its primary, in their order, wherever
    /// they stood; every other Space keeps its place.
    private static IReadOnlyList<SpaceState> Gathered(List<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var led = Led(spaces, pending);
        var following = led.Values.SelectMany(members => members).Select(member => member.Id).ToHashSet();
        var result = new List<SpaceState>(spaces.Count);
        foreach (var space in spaces) {
            if (following.Contains(space.Id)) continue;
            result.Add(space);
            if (led.TryGetValue(space.Id, out var members)) result.AddRange(members);
        }
        return result.SequenceEqual(spaces) ? spaces : result;
    }

    /// The Sub-Spaces that stay, by the primary they name, in session order.
    private static Dictionary<Guid, List<SpaceState>> Led(IReadOnlyList<SpaceState> spaces, IReadOnlySet<Guid> pending) {
        var led = new Dictionary<Guid, List<SpaceState>>();
        foreach (var space in spaces) {
            if (pending.Contains(space.Id) || space.PrimaryId is not { } primaryId) continue;
            if (!led.TryGetValue(primaryId, out var members)) led[primaryId] = members = [];
            members.Add(space);
        }
        return led;
    }

    /// Whether `space` leads a Sub-Space that stays.
    private static bool Leads(SpaceState space, IReadOnlyList<SpaceState> spaces, IReadOnlySet<Guid> pending) =>
        spaces.Any(other => other.PrimaryId == space.Id && !pending.Contains(other.Id));

    #endregion
}
