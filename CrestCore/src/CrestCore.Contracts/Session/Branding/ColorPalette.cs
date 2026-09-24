using System.Collections;

namespace CrestCore.Contracts;

/// <summary>An ordered set of colors, equal to another that holds the same colors.</summary>
public sealed class ColorPalette(IEnumerable<BrandColor> colors) : IReadOnlyList<BrandColor>, IEquatable<ColorPalette> {
    #region Variables

    private readonly BrandColor[] colors = [.. colors];

    public int Count => colors.Length;

    public BrandColor this[int index] => colors[index];

    #endregion

    #region Actions - Enumeration

    public IEnumerator<BrandColor> GetEnumerator() => ((IEnumerable<BrandColor>)colors).GetEnumerator();

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();

    #endregion

    #region Actions - Equality

    public bool Equals(ColorPalette? other) => other is not null && colors.SequenceEqual(other.colors);

    public override bool Equals(object? obj) => Equals(obj as ColorPalette);

    public override int GetHashCode() => colors.Aggregate(colors.Length, HashCode.Combine);

    #endregion
}
