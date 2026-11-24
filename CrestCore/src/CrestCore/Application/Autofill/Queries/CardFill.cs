using System.Text;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What filling `Card` into the form of `Fields` writes, from the field whose
/// `FormField.Index` is `Focused`: a value for each field of the card section
/// that holds it, and nothing outside that section. The security code is
/// written only when the card keeps one. A focused field in no card section
/// fills nothing. Refused with `InvalidAutofillRecord` when the card breaks
/// its limits. It reads nothing the app holds.
[HoldsSecrets]
public sealed record CardFill(IReadOnlyList<FormField> Fields, int Focused, CardRecord Card) : StandaloneQuery<AutofillPlan> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override AutofillPlan Answer(StandaloneContext context) {
        ArgumentNullException.ThrowIfNull(Fields);
        ArgumentNullException.ThrowIfNull(Card);
        var card = Card.Validated();
        return AutofillSection.Understand(Fields, Focused) is { } section
            ? section.Plan(Fields, new AutofillFilling(section, Fields, null, card)) : AutofillPlan.Empty;
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CardFill { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name nothing of the card.
    protected override bool PrintMembers(StringBuilder builder) {
        builder.Append($"Fields = {Fields.Count}, Focused = {Focused}, Card = <redacted>");
        return true;
    }

    #endregion
}
