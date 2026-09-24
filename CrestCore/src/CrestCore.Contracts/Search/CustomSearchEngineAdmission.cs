namespace CrestCore.Contracts;

/// The engine Crest would save for `Engine`, trimmed and validated, next to
/// the Space's `Existing` custom engines. An edited engine keeps its identity,
/// so it may keep its own name.
public sealed record CustomSearchEngineAdmission(CustomSearchEngine Engine, IReadOnlyList<CustomSearchEngine> Existing)
    : Query<CustomSearchEngine>;
