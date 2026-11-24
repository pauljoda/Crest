using CrestCore.Contracts;

namespace CrestCore.Domain;

/// One fill of a form's section: the section, the form's fields, and the
/// address or the card it writes. A role of the other kind finds nothing to
/// write, so filling an address into a card section writes nothing.
[HoldsSecrets]
internal sealed class AutofillFilling(AutofillSection section, IReadOnlyList<FormField> fields, AddressRecord? address,
    CardRecord? card) {
    #region Variables

    public AutofillSection Section { get; } = section;

    public AddressRecord? Address { get; } = address;

    public CardRecord? Card { get; } = card;

    #endregion

    #region Actions - Reading

    /// Whether the section holds a field of `role`.
    public bool Has(AutofillFieldRole role) => Section.Has(role);

    /// The section's fields of `role`, in the page's order.
    public IReadOnlyList<FormField> FieldsOf(AutofillFieldRole role) => [.. Section.Fields.Where(reading => reading.Role == role)
        .Select(reading => SignInForm.FieldAt(fields, reading.Field)).OfType<FormField>()];

    #endregion

    #region Actions - Text

    public override string ToString() => $"AutofillFilling {{ Kind = {Section.Kind.Name}, Fields = {Section.Fields.Count} }}";

    #endregion
}
