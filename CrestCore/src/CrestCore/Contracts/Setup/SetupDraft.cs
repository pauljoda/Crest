namespace CrestCore.Contracts;

/// A manual setup in progress over the workspace `WorkspaceId`: its Spaces as
/// the person is setting them up, each an existing Space or a new one, in the
/// order the workspace takes when `OrderWasEdited`. The device holds one setup
/// at a time and follows Spaces changed elsewhere while it waits: an existing
/// Space deleted meanwhile leaves it, and one created meanwhile joins at the
/// end. `ApplyManualSetup` applies it. Each edit answers the setup as it
/// leaves it: the Spaces it starts from, the name and look a new Space takes,
/// and how far it may grow.
public sealed record SetupDraft(Guid WorkspaceId, IReadOnlyList<SetupDraftSpace> Spaces, bool OrderWasEdited) {
    #region Static Variables

    /// The symbol a new Space of a setup wears until the person picks one.
    internal const string NewSpaceSymbol = "square.grid.2x2.fill";

    #endregion

    #region Actions - Starting

    /// A setup of the Spaces `session` keeps, in their order, with a new Space
    /// when there are none.
    internal static SetupDraft Started(Guid workspaceId, SessionState session, Func<Guid> nextId) {
        ArgumentNullException.ThrowIfNull(session);
        var draft = new SetupDraft(workspaceId, [.. session.StayingSpaces.Select(SetupDraftSpace.Existing)], OrderWasEdited: false);
        return draft.Spaces.Count == 0 ? draft.Adding(nextId) : draft;
    }

    /// The setup following the Spaces `session` keeps now: an existing Space
    /// deleted meanwhile, or going away, leaves it, every other Space keeps
    /// its place and choices, and a Space created meanwhile joins at the end.
    internal SetupDraft Reconciled(SessionState session) {
        ArgumentNullException.ThrowIfNull(session);
        var spaces = session.StayingSpaces;
        var current = spaces.Select(space => space.Id).ToHashSet();
        var kept = Spaces.Where(space => space.IsNew || current.Contains(space.SpaceId)).DistinctBy(space => space.SpaceId).ToList();
        var named = kept.Select(space => space.SpaceId).ToHashSet();
        kept.AddRange(spaces.Where(space => !named.Contains(space.Id)).Select(SetupDraftSpace.Existing));
        return kept.Count == Spaces.Count && kept.SequenceEqual(Spaces) ? this : this with { Spaces = kept };
    }

    #endregion

    #region Actions - Editing

    /// The setup with a new Space at its end, named for its place and wearing
    /// the accents in turn, and the house look of its accent. Throws `Rejected`
    /// with `SpaceLimitReached` when the setup holds as many Spaces as a
    /// workspace may.
    internal SetupDraft Adding(Func<Guid> nextId) {
        ArgumentNullException.ThrowIfNull(nextId);
        int count = Spaces.Count;
        if (count >= SessionState.MaximumSpaces) throw new Rejected(new SpaceLimitReached(SessionState.MaximumSpaces));
        var accent = SpaceAccent.All[count % SpaceAccent.All.Count];
        var space = new SetupDraftSpace(nextId(), nextId(), IsNew: true,
            new($"Space {count + 1}", NewSpaceSymbol, accent, accent.House));
        return this with { Spaces = [.. Spaces, space] };
    }

    /// The setup without the new Space `spaceId`. An existing Space stays.
    internal SetupDraft Removing(Guid spaceId) =>
        Spaces.Any(space => space.SpaceId == spaceId && space.IsNew)
            ? this with { Spaces = [.. Spaces.Where(space => space.SpaceId != spaceId)] }
            : this;

    /// The setup with `spaceId` where `targetId` stands, keeping its order.
    internal SetupDraft Moving(Guid spaceId, Guid targetId) {
        var spaces = Spaces.ToList();
        int source = spaces.FindIndex(space => space.SpaceId == spaceId), target = spaces.FindIndex(space => space.SpaceId == targetId);
        if (source < 0 || target < 0 || source == target) return this;
        var moved = spaces[source];
        spaces.RemoveAt(source);
        spaces.Insert(target, moved);
        return this with { Spaces = spaces, OrderWasEdited = true };
    }

    /// The setup with `spaceId` taking `customization`, its look kept within
    /// the ranges every device draws and its name as typed.
    internal SetupDraft Customizing(Guid spaceId, SpaceCustomization customization) {
        ArgumentNullException.ThrowIfNull(customization);
        var kept = customization with { Branding = SpaceBranding.Normalized(customization.Branding) };
        return this with {
            Spaces = [.. Spaces.Select(space => space.SpaceId == spaceId ? space with { Customization = kept } : space)]
        };
    }

    #endregion
}
