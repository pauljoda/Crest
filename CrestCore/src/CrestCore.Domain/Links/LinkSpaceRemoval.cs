namespace CrestCore.Domain;

/// What a deleted Space leaves behind in the link preferences: the routes that
/// survive in order, whether the chosen external-link Space is cleared, and
/// whether sites remembered for the deleted Space are forgotten.
public sealed record LinkSpaceRemoval(IReadOnlyList<Guid> RetainedRouteIds, bool ClearsChosenSpace, bool ForgetsRememberedSites);
