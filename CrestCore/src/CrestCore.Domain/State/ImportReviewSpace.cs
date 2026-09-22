namespace CrestCore.Domain;

/// An imported or existing Space as the import review sees it.
public sealed record ImportReviewSpace(Guid Id, string Name, IReadOnlyList<ImportReviewTab> Tabs);
