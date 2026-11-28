namespace CrestCore.Contracts;

/// A page's script dialog waits on the person.
public sealed record ScriptDialogAsked(Guid PromptId, Guid PageId, ScriptDialogQuestion Question) : Change {
    #region Actions - Prompts

    /// The prompt it asks, which waits until a `PromptSettled` for it.
    internal override Guid? AskedPromptId => PromptId;

    #endregion
}
