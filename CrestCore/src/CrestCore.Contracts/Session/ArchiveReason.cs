namespace CrestCore.Contracts;

/// <summary>Why a tab moved to its Space's archive.</summary>
public enum ArchiveReason {
    /// <summary>Current-tab cleanup archived a tab nobody had used for its lifetime.</summary>
    AutoCleanup,
    Closed,
    /// <summary>A saved or pinned tab the person deleted. Unlike a close, this is
    /// the evidence that authorizes an explicit sync deletion.</summary>
    Deleted,
    /// <summary>An explicit deletion first confirmed by another device.</summary>
    DeletedOnAnotherDevice,
    QuickWindow,
    /// <summary>An archive record first observed from another device.</summary>
    Synced
}
