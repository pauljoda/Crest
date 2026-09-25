namespace CrestCore.Contracts;

/// The image of a page's icon as its engine found it, or nothing.
public sealed record PageIconImage(byte[]? Image);
