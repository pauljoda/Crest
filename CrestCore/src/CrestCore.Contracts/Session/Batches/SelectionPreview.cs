namespace CrestCore.Contracts;

/// What the tabs and folders a person picked in a Space's sidebar hold, as a
/// window shows it before it acts on them: the picks no picked folder holds, in
/// sidebar order, and every tab and folder they hold. A pick the Space does not
/// hold, and a Start Page, which the sidebar lists nowhere, are left out. A
/// preview reads a locked Space as a person sees it; only an action refuses it.
public sealed record SelectionPreview(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<Guid> TabIds, IReadOnlyList<Guid> FolderIds)
    : Query<SelectedTabs>;
