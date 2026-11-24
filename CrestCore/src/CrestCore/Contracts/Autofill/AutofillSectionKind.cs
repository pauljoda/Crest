namespace CrestCore.Contracts;

/// What one section of a form takes: an address, with the person's name,
/// email address and phone number, or a payment card. Each kind says when a
/// section of it is worth filling: an address section holds at least three
/// different kinds of field, so a lone name or newsletter box is never one,
/// and a card section holds a card number, or a field the page declares, as
/// a card form split across frames does. A kind travels as its index in
/// `All`, so `All` is append-only.
public sealed class AutofillSectionKind {
    #region Static Variables

    /// The fewest roles an address section holds.
    private const int MinimumAddressRoles = 3;

    public static readonly AutofillSectionKind Address = new(name: "address",
        isFillable: section => section.Fields.Select(reading => reading.Role).Distinct().Count() >= MinimumAddressRoles);

    public static readonly AutofillSectionKind Card = new(name: "card",
        isFillable: section => section.Has(AutofillFieldRole.CardNumber) || section.Fields.Any(reading => reading.IsDeclared));

    public static IReadOnlyList<AutofillSectionKind> All { get; } = [Address, Card];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether a section of this kind is worth filling.
    private readonly Func<AutofillSection, bool> isFillable;

    #endregion

    #region Constructors

    private AutofillSectionKind(string name, Func<AutofillSection, bool> isFillable) {
        Name = name;
        this.isFillable = isFillable;
    }

    #endregion

    #region Actions - Lookup

    public static AutofillSectionKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion

    #region Actions - Reading

    /// Whether `section`, of this kind, is worth filling.
    internal bool Fills(AutofillSection section) => isFillable(section);

    #endregion
}
