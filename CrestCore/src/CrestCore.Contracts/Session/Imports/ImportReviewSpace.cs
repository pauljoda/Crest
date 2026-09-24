namespace CrestCore.Contracts;

/// A Space as the review of an import reads it: its identity, its name, and
/// each tab's identity, address and placement.
public sealed record ImportReviewSpace(Guid Id, string Name, IReadOnlyList<ImportReviewTab> Tabs);
