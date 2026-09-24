namespace CrestCore.Contracts;

/// <summary>An ordered set of colors, equal to another that holds the same colors.</summary>
public sealed record ColorPalette(IReadOnlyList<BrandColor> Colors) {
    #region Actions - Equality

    public bool Equals(ColorPalette? other) => other is not null && Colors.SequenceEqual(other.Colors);

    public override int GetHashCode() => Colors.Aggregate(Colors.Count, HashCode.Combine);

    #endregion
}
