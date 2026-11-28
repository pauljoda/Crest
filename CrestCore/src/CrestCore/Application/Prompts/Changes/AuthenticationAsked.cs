namespace CrestCore.Contracts;

/// A server's request for a user name and password waits on the person.
public sealed record AuthenticationAsked(Guid PromptId, Guid PageId, AuthenticationQuestion Question) : Change {
    #region Actions - Prompts

    /// The prompt it asks, which waits until a `PromptSettled` for it.
    internal override Guid? AskedPromptId => PromptId;

    #endregion
}
