using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Spaces

    private static SpaceDeletionState? PendingDeletion(SessionState value, Guid spaceId) =>
        value.SpaceDeletions.FirstOrDefault(deletion => deletion.SpaceId == spaceId);

    /// `space` with `settings`, keeping the settings it had when nothing
    /// changed, so an edit that changes nothing publishes nothing.
    private static SpaceState Configured(SpaceState space, SpaceSettings settings) =>
        settings == space.Settings ? space : space with { Settings = settings };

    /// Refuses a Space intent a borrowed workspace cannot apply: the
    /// workspace it borrows from owns the Space's profile and its settings,
    /// and makes, orders and deletes Spaces.
    private void RequireOwnedSpaces() {
        if (!workspaceKind.OwnsSpaces) throw new Rejected(new BorrowedProfileRequiresOwner(workspaceId));
    }

    /// `basis` with the Space an intent edited in its place.
    private SessionEdit SettingSpace(SessionState basis, SpaceState space, Func<SpaceSettings, SpaceSettings> edit, SyncStaging staging) =>
        new(Replacing(basis, Configured(space, edit(space.Settings))), staging);

    private SessionEdit CreatingSpace(SessionState basis, CreateSpace intent, DateTimeOffset now, IIdSource ids) {
        RequireOwnedSpaces();
        if (basis.Spaces.Any(space => space.Id == intent.SpaceId)) throw new Rejected(new SpaceAlreadyExists(intent.SpaceId));
        if (basis.Spaces.Count >= BrowserLimits.Spaces) throw new Rejected(new SpaceLimitReached(BrowserLimits.Spaces));
        var space = SpaceTemplate.For(workspaceKind.IsPrivate)
            .Make(intent.SpaceId, ids.Next(), ids.Next(), basis.Spaces.Count + 1, now);
        // A new Space is the one its window shows next, on its only tab.
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId)).ShowSpace(space.Id).ShowTab(space.Id, space.Tabs[0].Id);
        return new(basis with { Spaces = [.. basis.Spaces, space] }, SyncStaging.Creation, followUp);
    }

    private SessionEdit SettingIdentity(SessionState basis, SetSpaceIdentity intent) {
        RequireOwnedSpaces();
        var space = Editable(basis, intent.SpaceId);
        var name = SpaceOrganizationPolicy.ChosenName(intent.Name);
        return SettingSpace(basis, space, settings => settings with {
            Name = name,
            Symbol = SpaceOrganizationPolicy.Symbol(intent.Symbol),
            Accent = intent.Accent
        }, SyncStaging.Edit);
    }

    private SessionEdit SettingBranding(SessionState basis, SetSpaceBranding intent) {
        RequireOwnedSpaces();
        var branding = SpaceBrandingPolicy.Normalize(intent.Branding);
        return SettingSpace(basis, Editable(basis, intent.SpaceId), settings => settings with { Branding = branding }, SyncStaging.Edit);
    }

    private SessionEdit SettingCredentials(SessionState basis, SetCredentialPreferences intent) {
        RequireOwnedSpaces();
        return SettingSpace(basis, Editable(basis, intent.SpaceId), settings => settings with { CredentialPreferences = intent.Preferences },
            SyncStaging.Protection);
    }

    /// Asking for authentication is always allowed, even for a locked Space;
    /// letting a Space open freely is the decision authentication guards.
    private SessionEdit SettingAccess(SessionState basis, SetSpaceAccess intent) {
        RequireOwnedSpaces();
        var space = Editable(basis, intent.SpaceId, maintains: intent.Policy != SpaceAccessPolicy.Open);
        return SettingSpace(basis, space, settings => settings with { AccessPolicy = intent.Policy }, SyncStaging.Protection);
    }

    private SessionEdit SettingDefault(SessionState basis, SetDefaultSpace intent) {
        RequireOwnedSpaces();
        var space = Editable(basis, intent.SpaceId);
        return new(basis.DefaultSpaceId == space.Id ? basis : basis with { DefaultSpaceId = space.Id }, SyncStaging.Edit);
    }

    private SessionEdit Reordering(SessionState basis, ReorderSpaces intent) {
        RequireOwnedSpaces();
        var byId = basis.Spaces.ToDictionary(space => space.Id);
        if (intent.SpaceIds.Count != byId.Count || intent.SpaceIds.Distinct().Count() != byId.Count || intent.SpaceIds.Any(id => !byId.ContainsKey(id)))
            throw new Rejected(new InvalidSpaceOrder());
        return new(basis.Spaces.Select(space => space.Id).SequenceEqual(intent.SpaceIds)
            ? basis : basis with { Spaces = [.. intent.SpaceIds.Select(id => byId[id])] }, SyncStaging.Edit);
    }

    private SessionEdit ExpandingSavedTabs(SessionState basis, ExpandSavedTabs intent, DateTimeOffset now) {
        RequireOwnedSpaces();
        var space = Editable(basis, intent.SpaceId);
        return space.Settings.IsSavedTabsExpanded == intent.IsExpanded ? new(basis, SyncStaging.Edit)
            : SettingSpace(basis, space, settings => settings with { IsSavedTabsExpanded = intent.IsExpanded, SavedTabsExpansionModifiedAt = now },
                SyncStaging.Edit);
    }

    #endregion

    #region Actions - Space deletion

    /// The Space a deletion names, locked or not, and its deletion under way.
    private static (SpaceState Space, SpaceDeletionState? Pending) Deleting(SessionState basis, Guid spaceId) =>
        (basis.Spaces.FirstOrDefault(space => space.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId)),
            PendingDeletion(basis, spaceId));

    /// Records the deletion, which leaves the Space as it is until it is
    /// removed. The window showing a Space that is going away moves to the
    /// first one that stays.
    private SessionEdit BeginningDeletion(SessionState basis, BeginDeletingSpace intent) {
        RequireOwnedSpaces();
        var (space, pending) = Deleting(basis, intent.SpaceId);
        if (pending is not null)
            return pending.Id == intent.OperationId ? new(basis, SyncStaging.Withdrawal) : throw new Rejected(new WrongDeletionOperation(space.Id));
        SpaceOrganizationPolicy.RequireRemovable(basis.Spaces.Count - basis.SpaceDeletions.Count);
        var next = basis with { SpaceDeletions = [.. basis.SpaceDeletions, new(intent.OperationId, space.Id, space.ProfileId)] };
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId));
        if (followUp.Window?.ShownSpaceId == space.Id)
            followUp.ShowSpace(next.Spaces.First(candidate => PendingDeletion(next, candidate.Id) is null).Id);
        return new(next, SyncStaging.Withdrawal, followUp);
    }

    /// Removes the Space and its deletion. The Space that takes its place is
    /// where its window goes and, when it was the launch Space, the new one.
    private SessionEdit FinishingDeletion(SessionState basis, FinishDeletingSpace intent) {
        RequireOwnedSpaces();
        var (space, pending) = Deleting(basis, intent.SpaceId);
        if (pending is null || pending.Id != intent.OperationId) throw new Rejected(new WrongDeletionOperation(space.Id));
        SpaceOrganizationPolicy.RequireRemovable(basis.Spaces.Count);
        var index = basis.Spaces.ToList().IndexOf(space);
        var spaces = basis.Spaces.Where(candidate => candidate.Id != space.Id).ToArray();
        var neighbor = spaces[Math.Min(index, spaces.Length - 1)].Id;
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId));
        if (followUp.Window?.ShownSpaceId == space.Id) followUp.ShowSpace(neighbor);
        return new(basis with {
            Spaces = spaces,
            SpaceDeletions = [.. basis.SpaceDeletions.Where(deletion => deletion != pending)],
            DefaultSpaceId = basis.DefaultSpaceId == space.Id ? neighbor : basis.DefaultSpaceId
        }, SyncStaging.Removal, followUp);
    }

    /// A private workspace starts over with one fresh private Space, which
    /// the window that asked shows. Nothing it held ever synced.
    private SessionEdit ResettingPrivateBrowsing(SessionState basis, ResetPrivateBrowsing intent, DateTimeOffset now, IIdSource ids) {
        if (!workspaceKind.IsPrivate) throw new Rejected(new NotPrivateWorkspace(workspaceId));
        var space = SpaceTemplate.Private.Make(ids.Next(), ids.Next(), ids.Next(), number: 1, now);
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId)).ShowSpace(space.Id).ShowTab(space.Id, space.Tabs[0].Id);
        return new(basis with { Spaces = [space], SpaceDeletions = [], DefaultSpaceId = null }, Staging: null, followUp);
    }

    #endregion
}
