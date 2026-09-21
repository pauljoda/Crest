namespace CrestCore.Domain;

public sealed record SplitJoin(TabId SelectedTab, IReadOnlyList<(TabId Source, TabId Copy)> Copies);
