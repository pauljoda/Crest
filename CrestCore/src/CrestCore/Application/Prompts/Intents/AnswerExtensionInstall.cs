using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person answered whether to install an extension, whether it installs
/// with its site access withheld, and, when they accept, the other Spaces
/// `CopySpaceIds` it goes to as well.
public sealed record AnswerExtensionInstall(Guid PromptId, bool Accepted, bool WithholdsSiteAccess,
    IReadOnlyList<Guid> CopySpaceIds) : PromptIntent(PromptId) {
    #region Actions - Prompts

    internal override void Apply(CrestApp app, ChangeFeed changes) => app.Extensions.Answer(this, changes, app.Issue);

    #endregion
}
