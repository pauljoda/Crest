namespace CrestCore.Contracts;

/// `Mode` could make no icon from what the intent gave: an emoji icon needs an
/// emoji.
public sealed record InvalidTabIcon(TabIconMode Mode) : Rejection;
