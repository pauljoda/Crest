namespace CrestCore.Contracts;

/// <summary>
/// What a person chose for a split: its name, icon and tint, each with the time it
/// last changed so devices merge the fields independently. Membership stays on the
/// tabs, whose <see cref="TabState.SplitGroupId"/> names this group.
/// </summary>
public sealed record SplitGroupState(
    Guid Id,
    string? CustomTitle = null,
    DateTimeOffset? TitleModifiedAt = null,
    string? CustomIconSymbol = null,
    DateTimeOffset? IconModifiedAt = null,
    BrandColor? Tint = null,
    DateTimeOffset? TintModifiedAt = null);
