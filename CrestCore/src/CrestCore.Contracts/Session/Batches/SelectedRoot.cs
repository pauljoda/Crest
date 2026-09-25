namespace CrestCore.Contracts;

/// A pick no picked folder holds: a tab, or a folder with everything in it.
public sealed record SelectedRoot(Guid Id, SidebarRowKind Kind);
