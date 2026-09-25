namespace CrestCore.Contracts;

/// A rectangle of a page's view, in points from its top left.
public sealed record PageArea(double X, double Y, double Width, double Height);
