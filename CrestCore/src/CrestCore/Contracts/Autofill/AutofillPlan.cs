using System.Text;

namespace CrestCore.Contracts;

/// What a fill writes into a form: a value for each field of the focused
/// section it has one for, in the page's order. A field it names no value
/// for is left as it is, and a fill from a field in no section writes nothing.
[HoldsSecrets]
public sealed record AutofillPlan(IReadOnlyList<AutofillValue> Values) {
    #region Static Variables

    /// A plan that writes nothing.
    internal static AutofillPlan Empty { get; } = new([]);

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("AutofillPlan { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no value.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Values = {Values.Count}");
        return true;
    }

    #endregion
}
