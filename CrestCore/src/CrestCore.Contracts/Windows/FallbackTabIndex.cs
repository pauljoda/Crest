namespace CrestCore.Contracts;

/// The index of a draft Space's fallback tab among the placements asked
/// about, or null for a Space without tabs.
public sealed record FallbackTabIndex(int? Index);
