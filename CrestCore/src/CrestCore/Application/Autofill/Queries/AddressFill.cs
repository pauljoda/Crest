using System.Text;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What filling `Address` into the form of `Fields` writes, from the field
/// whose `FormField.Index` is `Focused`: a value for each field of the
/// address section that holds it, and nothing outside that section. A focused
/// field in no address section fills nothing. Refused with
/// `InvalidAutofillRecord` when the address breaks its limits. It reads
/// nothing the app holds.
[HoldsSecrets]
public sealed record AddressFill(IReadOnlyList<FormField> Fields, int Focused, AddressRecord Address) : StandaloneQuery<AutofillPlan> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override AutofillPlan Answer(StandaloneContext context) {
        ArgumentNullException.ThrowIfNull(Fields);
        ArgumentNullException.ThrowIfNull(Address);
        var address = Address.Validated();
        return AutofillSection.Understand(Fields, Focused) is { } section
            ? section.Plan(Fields, new AutofillFilling(section, Fields, address, null)) : AutofillPlan.Empty;
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("AddressFill { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name nothing of the address.
    protected override bool PrintMembers(StringBuilder builder) {
        builder.Append($"Fields = {Fields.Count}, Focused = {Focused}, Address = <redacted>");
        return true;
    }

    #endregion
}
