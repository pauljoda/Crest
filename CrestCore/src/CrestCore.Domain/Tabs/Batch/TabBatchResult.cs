namespace CrestCore.Domain;

public sealed record TabBatchResult(Guid? Selection, Guid? DestinationSelection,
    IReadOnlyList<(Guid Source, Guid Copy)> Copies, IReadOnlyList<(Guid Source, Guid Copy)> GroupCopies,
    Guid? CreatedFolder);
