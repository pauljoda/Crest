namespace CrestCore.Contracts;

/// <summary>The gradient each of a palette's colors runs on into, by the color's
/// index. A color past the end of <see cref="Slots"/>, or whose gradient has no
/// colors, is plain. Equal to another that holds the same gradients.</summary>
public sealed record PaletteGradients(IReadOnlyList<BrandGradient> Slots) {
    #region Variables

    /// The set owns its gradients, including when a copy replaces them.
    public IReadOnlyList<BrandGradient> Slots {
        get;
        init => field = [.. value];
    } = [.. Slots];

    #endregion

    #region Actions - Equality

    public bool Equals(PaletteGradients? other) => other is not null && Slots.SequenceEqual(other.Slots);

    public override int GetHashCode() => Slots.Aggregate(Slots.Count, HashCode.Combine);

    #endregion
}
