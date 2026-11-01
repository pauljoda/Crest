using CrestCore.Application;

namespace CrestCore.Contracts;

/// Imports the review setup holds for the workspace, as its choices say. An
/// included Space becomes a new Space or joins the existing one it names,
/// taking the name and look the review gives it, with the tabs the review
/// includes in the placements it chose and the saved folders those tabs need;
/// a folder matches one the destination holds by title. Pinned tabs past a
/// destination's limit become saved tabs in an `Imported Pinned Tabs` folder.
/// A new Space keeps its archive and history. Spaces that shared one session
/// where they came from, as an Arc profile's do, keep sharing one: they come
/// in as one group, or, when the review brings one of them into an existing
/// Space, the others join that Space's group as its Sub-Spaces, opening with
/// it here and reached by the agents that reach it. Over a first launch's
/// disposable Spaces, the reviewed Spaces replace them.
///
/// Refused with `NoSetup` when setup holds no review for the workspace, and
/// `NoIncludedSpaces` when the review includes none.
public sealed record ImportReviewedSpaces(Guid WorkspaceId, Guid WindowId) : ImportWorkspace(WorkspaceId, WindowId) {
    #region Actions - Session

    /// Imports the review setup holds for this workspace; see
    /// `ImportReviewedSpaces`.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (!workspace.Kind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(workspace.WorkspaceId));
        var review = workspace.Device?.ImportReview(workspace.WorkspaceId) ?? throw new Rejected(new NoSetup());
        return workspace.Importing(turn.Basis, this, [.. review.Spaces.Select(space => space.Source)], turn.Previewed, turn.Now, turn.Ids,
            import => import.ImportReviewed(review, turn.Ids, turn.Now));
    }

    #endregion

    #region Actions - Routing

    /// Each new Space the import brought into a group the workspace already
    /// held opens with that group while this process holds its grant, and
    /// shares the group's agent access and site permissions, as joining it
    /// would.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        var before = app.Device.Workspace(WorkspaceId).Current;
        base.Commit(app, changes);
        var session = app.Device.Workspace(WorkspaceId).Current;
        foreach (var joined in session.Spaces.Where(space => before.Space(space.Id) is null && space.PrimaryId is { } primaryId
            && before.Space(primaryId) is not null)) {
            if (session.GroupOf(joined.Id) is not { } group) continue;
            app.Access.Changing(changes, authority => authority.Extend(new(group.Primary.Id, group.Primary.OwnProfileId),
                new(joined.Id, joined.OwnProfileId)));
            app.Device.ShareAgents(joined.Id, group.Primary.Id, changes);
            app.Device.ShareSitePermissions(joined.Id, changes);
        }
    }

    #endregion
}
