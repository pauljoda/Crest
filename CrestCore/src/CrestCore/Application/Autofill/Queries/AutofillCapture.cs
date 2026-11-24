using System.Text;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What a form of `Fields`, sent holding `Values`, offers to keep: the first
/// address section the person entered something in that names a street and
/// a postal code or city, and the first card section the person entered
/// something in whose number is complete and whose expiry is a month of a
/// year. `Values` name each field by its `FormField.Index`, a select's by
/// its chosen option's value; a field named twice keeps its first value. The
/// security code a form sends is never kept. It reads nothing the app holds.
[HoldsSecrets]
public sealed record AutofillCapture(IReadOnlyList<FormField> Fields, IReadOnlyList<AutofillValue> Values)
    : StandaloneQuery<AutofillProposal> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override AutofillProposal Answer(StandaloneContext context) {
        ArgumentNullException.ThrowIfNull(Fields);
        ArgumentNullException.ThrowIfNull(Values);
        var values = new Dictionary<int, string>();
        foreach (var value in Values) values.TryAdd(value.Field, value.Value);
        var drafts = AutofillSection.Read(Fields).Select(section => section.Draft(Fields, values)).OfType<AutofillDraft>().ToList();
        var proposal = new AutofillProposal(drafts.Select(draft => draft.Address()).OfType<AddressRecord>().FirstOrDefault(),
            drafts.Select(draft => draft.Card()).OfType<CardRecord>().FirstOrDefault());
        return proposal.Address is null && proposal.Card is null ? AutofillProposal.Nothing : proposal;
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("AutofillCapture { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no value.
    protected override bool PrintMembers(StringBuilder builder) {
        builder.Append($"Fields = {Fields.Count}, Values = {Values.Count}");
        return true;
    }

    #endregion
}
