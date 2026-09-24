namespace CrestCore.Contracts;

/// What a person's review of the imported `Sources` means, one review for
/// each: the tabs each destination already holds, the destination tabs each
/// included Space matches, and the pinned tabs past a destination's limit.
/// Refused with `InvalidImport` when the reviews do not pair with the sources.
public sealed record ImportReviewAnalysis(Guid WorkspaceId, IReadOnlyList<ImportReviewSpace> Sources, IReadOnlyList<SpaceReview> Reviews)
    : Query<AnalyzedImportReview>;
