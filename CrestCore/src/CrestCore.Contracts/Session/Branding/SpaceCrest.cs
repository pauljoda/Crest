namespace CrestCore.Contracts;

/// <summary>
/// The composition of a Space's crest. Layer color indices point into the crest's own
/// <see cref="Palette"/> when it has one, else into the Space's colors. A
/// <see cref="Charge"/> replaces the heraldic <see cref="Symbol"/> as the figure drawn.
/// </summary>
public sealed record SpaceCrest(
    CrestBackplate Backplate,
    CrestFieldDivision FieldDivision,
    CrestOrdinary Ordinary,
    CrestTrim Trim,
    CrestSymbol Symbol,
    CrestChargeLayout ChargeLayout,
    int BackplateColorIndex,
    int SecondaryFieldColorIndex,
    int OrdinaryColorIndex,
    int TrimColorIndex,
    int SymbolColorIndex,
    string? StartingPresetId,
    int EdgeColorIndex,
    ColorPalette? Palette,
    CrestCharge? Charge,
    double PlateScale,
    double EdgeWidth,
    int DivisionCount,
    CrestFinish Finish,
    double OrdinaryWidth,
    double TrimWeight,
    int TrimDetail,
    double ChargeScale,
    double ChargeOffset,
    CrestChargeWeight ChargeWeight,
    double SheenAngle,
    int SealTeeth,
    bool ShowsOutline,
    CrestDepth Depth);
