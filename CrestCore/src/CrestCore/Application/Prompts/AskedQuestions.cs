using CrestCore.Contracts;

namespace CrestCore.Application;

/// The changes that asked the questions still waiting on the person, oldest
/// first, so a read model that starts later hears them as the others did:
/// each one the core publishes, until its `PromptSettled`. It follows every
/// change the core publishes, from an intent's turn and from what the core
/// starts itself. An extension's install review settles otherwise and is not
/// kept. Never saved or synced.
internal sealed class AskedQuestions {
    #region Variables

    private readonly List<Change> asked = [];
    private readonly Lock gate = new();

    /// The questions still waiting, as the changes that asked them, oldest first.
    internal IReadOnlyList<Change> Waiting {
        get {
            lock (gate) return [.. asked];
        }
    }

    #endregion

    #region Actions - Following

    /// Keeps a change that asks a question, and lets go of the one a
    /// settlement answers.
    internal void Follow(Change change) {
        if (change is PromptSettled settled) {
            lock (gate) asked.RemoveAll(question => PromptOf(question) == settled.PromptId);
        } else if (PromptOf(change) is not null) {
            lock (gate) asked.Add(change);
        }
    }

    #endregion

    #region Actions - Rules

    private static Guid? PromptOf(Change change) => change switch {
        ScriptDialogAsked question => question.PromptId,
        AuthenticationAsked question => question.PromptId,
        PermissionAsked question => question.PromptId,
        DownloadApprovalAsked question => question.PromptId,
        DownloadDestinationAsked question => question.PromptId,
        QuitWithDownloadsAsked question => question.PromptId,
        _ => null,
    };

    #endregion
}
