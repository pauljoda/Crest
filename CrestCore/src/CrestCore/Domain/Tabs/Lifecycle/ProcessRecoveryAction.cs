namespace CrestCore.Domain;

/// What a page does when its renderer stops: reload, or show the failure.
public sealed class ProcessRecoveryAction {
    #region Static Variables

    public static readonly ProcessRecoveryAction Reload = new(reloads: true);
    public static readonly ProcessRecoveryAction ShowFailure = new(reloads: false);

    public static IReadOnlyList<ProcessRecoveryAction> All { get; } = [Reload, ShowFailure];

    #endregion

    #region Variables

    /// The page reloads and its engine brings the renderer back.
    public bool Reloads { get; }

    #endregion

    #region Constructors

    private ProcessRecoveryAction(bool reloads) => Reloads = reloads;

    #endregion
}
