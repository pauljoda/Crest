namespace CrestCore.Contracts;

/// A selection previewed in the Space it was made in. `Selection` is what the
/// actions on it take: its roots by kind, holding `Members` as the window saw
/// them. `Roots` are the picks no picked folder holds, in sidebar order;
/// `Members` every tab the selection holds, in sidebar order; `FolderIds` the
/// picked folders and every folder inside them, in sidebar order.
public sealed record SelectedTabs(TabSelection Selection, IReadOnlyList<SelectedRoot> Roots, IReadOnlyList<SelectedTab> Members,
    IReadOnlyList<Guid> FolderIds);
