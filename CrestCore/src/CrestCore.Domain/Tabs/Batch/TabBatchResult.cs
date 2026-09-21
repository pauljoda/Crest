namespace CrestCore.Domain;

public sealed record TabBatchResult(TabId? Selection, TabId? DestinationSelection,
    IReadOnlyList<(TabId Source, TabId Copy)> Copies, IReadOnlyList<(Guid Source, Guid Copy)> GroupCopies,
    FolderId? CreatedFolder);
