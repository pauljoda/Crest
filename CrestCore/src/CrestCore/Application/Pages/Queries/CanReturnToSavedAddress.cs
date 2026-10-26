using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether returning a saved or pinned tab to the address it belongs to would
/// change anything: its live address in `WindowId` differs from the saved
/// page, or its stored address does when no live address is available.
public sealed record CanReturnToSavedAddress(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId)
    : Query<SavedAddressReturn> {
    #region Actions - Answering

    /// Whether returning the tab to its saved address changes anything: its live
    /// pending or committed address differs, falling back to the stored address.
    /// A tab that belongs nowhere, is gone or lives in a locked Space does not.
    internal override SavedAddressReturn Answer(CrestApp app) {
        var workspace = app.Pages.Device.Workspace(WorkspaceId);
        if (workspace.Current.Space(SpaceId) is not { } space
            || workspace.IsLocked(space)
            || space.Tabs.FirstOrDefault(tab => tab.Id == TabId) is not { SavedAddress: { } saved } tab)
            return new(ChangesPage: false);
        var current = app.Pages.Showing(WorkspaceId, WindowId, tab.Id)?.Address ?? tab.Url;
        return new(ChangesPage: current is { } address && !new WebAddress(address).IsSamePage(new WebAddress(saved)));
    }

    #endregion
}
