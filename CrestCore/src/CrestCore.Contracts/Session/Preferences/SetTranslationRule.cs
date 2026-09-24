namespace CrestCore.Contracts;

/// Records whether pages in `SourceLanguage` are translated into
/// `TargetLanguage`. Region aliases of the source share one choice, so an
/// alias cannot get around turning translation off; a blank source changes
/// nothing.
public sealed record SetTranslationRule(Guid WorkspaceId, string SourceLanguage, string TargetLanguage, bool IsEnabled)
    : SessionIntent(WorkspaceId);
