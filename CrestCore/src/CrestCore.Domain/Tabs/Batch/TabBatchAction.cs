namespace CrestCore.Domain;

public sealed record TabBatchAction(TabBatchKind Kind, TabPlacement Placement = TabPlacement.Current,
    FolderId? Folder = null, TabId? Before = null, FolderId? BeforeFolder = null,
    TabId? Target = null, int? Index = null, bool KeepLoaded = false, bool Follow = false);
