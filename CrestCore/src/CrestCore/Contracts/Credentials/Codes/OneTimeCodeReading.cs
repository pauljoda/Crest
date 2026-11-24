using System.Text;

namespace CrestCore.Contracts;

/// A one-time code, and the times it is valid from and until, in seconds since
/// 1970: the start and end of the period it belongs to.
[HoldsSecrets]
public sealed record OneTimeCodeReading(string Code, double ValidFrom, double ValidUntil) {
    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("OneTimeCodeReading { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Code = <redacted>, ValidFrom = {ValidFrom}, ValidUntil = {ValidUntil}");
        return true;
    }

    #endregion
}
