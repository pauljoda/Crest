using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Rules for a manual setup before `ApplyManualSetup` applies it: the Spaces
/// it starts from, the name and look a new Space takes, how far it may grow,
/// and how it follows Spaces changed elsewhere while it waits.
public static class ManualSetupPolicy {
    #region Static Variables

    /// The symbol a new Space of a setup wears until the person picks one.
    public const string NewSpaceSymbol = "square.grid.2x2.fill";

    #endregion

    #region Actions - Starting

    /// A setup of the Spaces `session` keeps, in their order, with a new Space
    /// when there are none.
    public static SetupDraft Started(Guid workspaceId, SessionState session, Func<Guid> nextId) {
        var draft = new SetupDraft(workspaceId, [.. Staying(session).Select(Existing)], OrderWasEdited: false);
        return draft.Spaces.Count == 0 ? Adding(draft, nextId) : draft;
    }

    /// `draft` following the Spaces `session` keeps now: an existing Space
    /// deleted meanwhile, or going away, leaves it, every other Space keeps
    /// its place and choices, and a Space created meanwhile joins at the end.
    public static SetupDraft Reconciled(SetupDraft draft, SessionState session) {
        ArgumentNullException.ThrowIfNull(draft);
        var spaces = Staying(session);
        var current = spaces.Select(space => space.Id).ToHashSet();
        var kept = draft.Spaces.Where(space => space.IsNew || current.Contains(space.SpaceId)).DistinctBy(space => space.SpaceId).ToList();
        var named = kept.Select(space => space.SpaceId).ToHashSet();
        kept.AddRange(spaces.Where(space => !named.Contains(space.Id)).Select(Existing));
        return kept.Count == draft.Spaces.Count && kept.SequenceEqual(draft.Spaces) ? draft : draft with { Spaces = kept };
    }

    /// The Spaces of `session` that are not going away.
    private static IReadOnlyList<SpaceState> Staying(SessionState session) {
        ArgumentNullException.ThrowIfNull(session);
        return [.. session.Spaces.Where(space => session.SpaceDeletions.All(deletion => deletion.SpaceId != space.Id))];
    }

    private static SetupDraftSpace Existing(SpaceState space) {
        var settings = space.Settings;
        return new(space.Id, space.ProfileId, IsNew: false, new(settings.Name, settings.Symbol, settings.Accent, settings.Look));
    }

    #endregion

    #region Actions - Editing

    /// `draft` with a new Space at its end, named for its place and wearing
    /// the accents in turn, and the house look of its accent. Throws `Rejected`
    /// with `SpaceLimitReached` when the setup holds as many Spaces as a
    /// workspace may.
    public static SetupDraft Adding(SetupDraft draft, Func<Guid> nextId) {
        ArgumentNullException.ThrowIfNull(draft);
        ArgumentNullException.ThrowIfNull(nextId);
        int count = draft.Spaces.Count;
        if (count >= SessionState.MaximumSpaces) throw new Rejected(new SpaceLimitReached(SessionState.MaximumSpaces));
        var accent = SpaceAccent.All[count % SpaceAccent.All.Count];
        var space = new SetupDraftSpace(nextId(), nextId(), IsNew: true,
            new($"Space {count + 1}", NewSpaceSymbol, accent, accent.House));
        return draft with { Spaces = [.. draft.Spaces, space] };
    }

    /// `draft` without the new Space `spaceId`. An existing Space stays.
    public static SetupDraft Removing(SetupDraft draft, Guid spaceId) {
        ArgumentNullException.ThrowIfNull(draft);
        return draft.Spaces.Any(space => space.SpaceId == spaceId && space.IsNew)
            ? draft with { Spaces = [.. draft.Spaces.Where(space => space.SpaceId != spaceId)] }
            : draft;
    }

    /// `draft` with `spaceId` where `targetId` stands, keeping its order.
    public static SetupDraft Moving(SetupDraft draft, Guid spaceId, Guid targetId) {
        ArgumentNullException.ThrowIfNull(draft);
        var spaces = draft.Spaces.ToList();
        int source = spaces.FindIndex(space => space.SpaceId == spaceId), target = spaces.FindIndex(space => space.SpaceId == targetId);
        if (source < 0 || target < 0 || source == target) return draft;
        var moved = spaces[source];
        spaces.RemoveAt(source);
        spaces.Insert(target, moved);
        return draft with { Spaces = spaces, OrderWasEdited = true };
    }

    /// `draft` with `spaceId` taking `customization`, its look kept within
    /// the ranges every device draws and its name as typed.
    public static SetupDraft Customizing(SetupDraft draft, Guid spaceId, SpaceCustomization customization) {
        ArgumentNullException.ThrowIfNull(draft);
        ArgumentNullException.ThrowIfNull(customization);
        var kept = customization with { Branding = SpaceBranding.Normalized(customization.Branding) };
        return draft with {
            Spaces = [.. draft.Spaces.Select(space => space.SpaceId == spaceId ? space with { Customization = kept } : space)]
        };
    }

    #endregion
}
