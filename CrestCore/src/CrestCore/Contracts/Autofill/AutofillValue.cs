using System.Text;

namespace CrestCore.Contracts;

/// A value for one field of a form: the field at `Field`, its
/// `FormField.Index`, holds `Value`, which for a select is its chosen
/// option's.
[HoldsSecrets]
public sealed record AutofillValue(int Field, string Value) {
    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("AutofillValue { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no value.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Field = {Field}, Value = <redacted>");
        return true;
    }

    #endregion
}
