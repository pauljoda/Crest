namespace CrestCore.Domain;

public sealed record SplitJoin(Guid SelectedTab, IReadOnlyList<(Guid Source, Guid Copy)> Copies);
