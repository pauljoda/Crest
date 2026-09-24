namespace CrestCore.Contracts;

/// The starting review for each imported Space, in the order they came.
public sealed record SuggestedImportReview(IReadOnlyList<SuggestedSpaceReview> Spaces);
