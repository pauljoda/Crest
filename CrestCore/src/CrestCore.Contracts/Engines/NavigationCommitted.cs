namespace CrestCore.Contracts;

/// A page's navigation took effect at `Url`. A new document begins a record
/// of its own; a move within the document begins one only when it reaches
/// another page, since a fragment is part of the page it names.
public sealed record NavigationCommitted(Guid PageId, string Url, bool SameDocument) : EngineEvent;
