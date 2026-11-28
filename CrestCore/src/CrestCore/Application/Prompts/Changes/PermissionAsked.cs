namespace CrestCore.Contracts;

/// A site's permission request that its Space's choices do not answer waits
/// on the person.
public sealed record PermissionAsked(Guid PromptId, Guid PageId, PermissionQuestion Question) : Change {
    #region Actions - Prompts

    /// The prompt it asks, which waits until a `PromptSettled` for it.
    internal override Guid? AskedPromptId => PromptId;

    #endregion
}
