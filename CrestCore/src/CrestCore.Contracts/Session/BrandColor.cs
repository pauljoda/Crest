namespace CrestCore.Contracts;

/// <summary>A color a person chose for a Space, folder or split. Components run 0 through 1.</summary>
public sealed record BrandColor(double Red, double Green, double Blue, double Alpha = 1);
