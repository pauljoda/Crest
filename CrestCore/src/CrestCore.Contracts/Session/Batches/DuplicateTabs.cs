namespace CrestCore.Contracts;

/// Copies the tabs a person selected in a window to the end of the open tabs,
/// in the order the sidebar lists them, with identities the core gives them,
/// each published as `TabCopied`. A copy of a web page starts from where its
/// source's page is now, preferring the page the window shows. The copies of a
/// split's members form a split of their own, named, drawn and tinted as the
/// source split is.
public sealed record DuplicateTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId);
