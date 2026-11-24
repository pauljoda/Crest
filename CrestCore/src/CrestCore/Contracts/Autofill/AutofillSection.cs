using CrestCore.Domain;

namespace CrestCore.Contracts;

#region Types

/// How the core reads one field of a section: the field at `Field`, its
/// `FormField.Index`, has `Role`, which the page declared in its autocomplete
/// attribute when `IsDeclared` is true and the core inferred from its type
/// and names otherwise.
public sealed record AutofillFieldReading(int Field, AutofillFieldRole Role, bool IsDeclared);

#endregion

/// One part of a form that a fill writes into together: an address, with the
/// person's name and contact details, or a payment card, and how each of its
/// fields reads, in the page's order. A fill only ever writes into the one
/// section that holds the field the person focused, so a shipping address
/// never spills into the billing one beside it.
public sealed partial record AutofillSection(AutofillSectionKind Kind, IReadOnlyList<AutofillFieldReading> Fields) {
    #region Actions - Reading

    /// Whether the section holds a field of `role`.
    internal bool Has(AutofillFieldRole role) => Fields.Any(reading => reading.Role == role);

    /// Whether the section holds the field at `index`.
    internal bool Holds(int index) => Fields.Any(reading => reading.Field == index);

    #endregion

    #region Actions - Filling

    /// What filling `filling`'s address or card into this section writes:
    /// each field's value, a select's the `Value` of the option it chooses.
    /// A field with nothing to write, such as a select with no option for the
    /// value, is left as it is.
    internal AutofillPlan Plan(IReadOnlyList<FormField> fields, AutofillFilling filling) {
        ArgumentNullException.ThrowIfNull(fields);
        ArgumentNullException.ThrowIfNull(filling);
        var values = new List<AutofillValue>();
        foreach (var reading in Fields) {
            if (SignInForm.FieldAt(fields, reading.Field) is not { } field) continue;
            if (field.Fill(reading.Role.Spellings(field, filling)) is { } value) values.Add(new(reading.Field, value));
        }
        return new(values);
    }

    #endregion

    #region Actions - Capture

    /// What the section said when its form was sent with `values`, each a
    /// field's index and what it held, or null when the person entered none
    /// of them. A value longer than any record keeps is left out.
    internal AutofillDraft? Draft(IReadOnlyList<FormField> fields, IReadOnlyDictionary<int, string> values) {
        ArgumentNullException.ThrowIfNull(fields);
        ArgumentNullException.ThrowIfNull(values);
        var held = Fields.Select(reading => (Reading: reading, Field: SignInForm.FieldAt(fields, reading.Field),
                Value: values.TryGetValue(reading.Field, out string? value) ? value.Trim() : ""))
            .Where(entry => entry.Field is not null && entry.Value.Length is > 0 and <= AddressRecord.MaximumTextLength).ToList();
        if (!held.Any(entry => entry.Field!.EnteredByPerson)) return null;
        var draft = new AutofillDraft(this);
        foreach (var (reading, field, value) in held) reading.Role.Capture(draft, field!.SpellingsOf(value));
        return draft;
    }

    #endregion
}
