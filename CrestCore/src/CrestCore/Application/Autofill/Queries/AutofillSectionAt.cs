using CrestCore.Application;

namespace CrestCore.Contracts;

/// The address or card section of the form of `Fields` that holds the field
/// whose `FormField.Index` is `Focused`, with how each of its fields reads,
/// or none when that field is in no section worth filling. It carries what
/// the page says about the fields, never their values, and reads nothing the
/// app holds.
public sealed record AutofillSectionAt(IReadOnlyList<FormField> Fields, int Focused) : StandaloneQuery<AutofillSectionAnswer> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override AutofillSectionAnswer Answer(StandaloneContext context) {
        ArgumentNullException.ThrowIfNull(Fields);
        return new(AutofillSection.Understand(Fields, Focused));
    }

    #endregion
}
