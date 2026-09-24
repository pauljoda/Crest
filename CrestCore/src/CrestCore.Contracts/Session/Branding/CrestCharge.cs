namespace CrestCore.Contracts;

/// <summary>
/// A crest's custom figure: a heraldic <see cref="Symbol"/>, or <see cref="Text"/> naming
/// a system symbol, an emoji or the letters of a monogram in its <see cref="Style"/>.
/// </summary>
public sealed record CrestCharge(CrestChargeKind Kind, CrestSymbol? Symbol = null, string? Text = null,
    CrestMonogramStyle? Style = null);
