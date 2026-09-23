using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed record TabBatchAction(TabBatchKind Kind, TabPlacement Placement = TabPlacement.Current,
    Guid? Folder = null, Guid? Before = null, Guid? BeforeFolder = null,
    Guid? Target = null, int? Index = null, bool KeepLoaded = false, bool Follow = false);
