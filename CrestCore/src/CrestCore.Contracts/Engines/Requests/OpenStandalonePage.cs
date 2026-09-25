namespace CrestCore.Contracts;

/// Opens one of the engine's own pages, such as its feature flags, as a page
/// that belongs to Settings in the profile `ProfileId` names, hosted by the
/// window `WindowId` names, at `Url`. No tab owns it and the core never hears
/// of it. TRANSITIONAL until such pages open through the core.
public sealed record OpenStandalonePage(Guid PageId, Guid ProfileId, Guid WindowId, string Url) : PageRequest<bool>;
