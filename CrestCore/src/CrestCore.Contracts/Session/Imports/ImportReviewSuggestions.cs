namespace CrestCore.Contracts;

/// The review a person starts from for the imported `Sources`: each joins the
/// existing Space with the same name, and leaves out the tabs that Space
/// already holds. Over a first launch's disposable Spaces, everything imports
/// into new Spaces.
public sealed record ImportReviewSuggestions(Guid WorkspaceId, IReadOnlyList<ImportReviewSpace> Sources)
    : Query<SuggestedImportReview>;
