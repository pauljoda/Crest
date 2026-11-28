namespace CrestCore.Contracts;

/// Whether to quit and stop the `LiveDownloads` downloads still in progress
/// waits on the person, for the quit preparation `RequestId`.
public sealed record QuitWithDownloadsAsked(Guid PromptId, Guid RequestId, int LiveDownloads) : Change {
    #region Actions - Prompts

    /// The prompt it asks, which waits until a `PromptSettled` for it.
    internal override Guid? AskedPromptId => PromptId;

    #endregion
}
