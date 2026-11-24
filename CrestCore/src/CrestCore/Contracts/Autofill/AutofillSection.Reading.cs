namespace CrestCore.Contracts;

/// How the core divides a form's fields into sections.
public sealed partial record AutofillSection {
    #region Types

    /// A section while its fields are read: its kind, the section and mode
    /// its fields declare, once one does, and the fields so far.
    private sealed class Gathering(AutofillSectionKind kind, string? scope) {
        public AutofillSectionKind Kind { get; } = kind;

        public string? Scope { get; set; } = scope;

        public List<AutofillFieldReading> Readings { get; } = [];
    }

    #endregion

    #region Actions - Reading

    /// The section of `fields` that holds the field whose `FormField.Index` is
    /// `focused`, or null when that field is in none worth filling. This is
    /// what a focus offers and what a fill writes into.
    internal static AutofillSection? Understand(IReadOnlyList<FormField> fields, int focused) =>
        Read(fields).FirstOrDefault(section => section.Holds(focused));

    /// The sections of `fields` worth filling, in the page's order. Fields
    /// autofill reads, visible ones of the types it writes, are taken in the
    /// page's order: an address field joins the address section being read,
    /// and a card field the card section. A field starts a new section of its
    /// kind when it declares another section or mode than the one being read,
    /// or repeats a role the section already holds that does not repeat, as
    /// a billing address after a shipping one does. A field that declares
    /// neither takes the section being read.
    internal static IReadOnlyList<AutofillSection> Read(IReadOnlyList<FormField> fields) {
        ArgumentNullException.ThrowIfNull(fields);
        var gathered = new List<Gathering>();
        var reading = new Dictionary<AutofillSectionKind, Gathering>();
        foreach (var field in fields.Where(field => field.TakesAutofill)) {
            if (AutofillFieldRole.Read(field) is not (var fieldReading, var scope)) continue;
            var kind = fieldReading.Role.Kind;
            var section = reading.GetValueOrDefault(kind);
            bool fits = section is not null && (scope is null || section.Scope is null || section.Scope == scope)
                && (fieldReading.Role.Repeats || section.Readings.All(held => held.Role != fieldReading.Role));
            if (!fits) {
                section = new Gathering(kind, scope);
                gathered.Add(section);
                reading[kind] = section;
            }
            section!.Scope ??= scope;
            section.Readings.Add(fieldReading);
        }
        return [.. gathered.Select(section => new AutofillSection(section.Kind, section.Readings)).Where(section => section.Kind.Fills(section))];
    }

    #endregion
}
