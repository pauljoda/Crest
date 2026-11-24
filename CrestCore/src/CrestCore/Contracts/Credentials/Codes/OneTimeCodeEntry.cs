using System.Text;

namespace CrestCore.Contracts;

/// What to enter in the field at `Field`, a `FormField.Index`, to enter a
/// one-time code: the whole code, or one character of it.
[HoldsSecrets]
public sealed record OneTimeCodeEntry(int Field, string Text) {
    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("OneTimeCodeEntry { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Field = {Field}, Text = <redacted>");
        return true;
    }

    #endregion
}
