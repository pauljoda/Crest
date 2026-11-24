using System.Text;

using CrestCore.Application;

namespace CrestCore.Contracts;

/// What to enter in each of `Fields` to enter `Code`: the whole code in one
/// field, or one character in each split field. The core keeps nothing of it.
[HoldsSecrets]
public sealed record SpreadOneTimeCode(OneTimeCodeFields Fields, string Code) : Query<OneTimeCodeFill> {
    #region Variables

    /// It reads only the code it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override OneTimeCodeFill Answer(CrestApp app) {
        ArgumentNullException.ThrowIfNull(Fields);
        return Fields.Spread(Code);
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("SpreadOneTimeCode { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    protected override bool PrintMembers(StringBuilder builder) {
        builder.Append($"Fields = {Fields?.Fields.Count ?? 0}, Code = <redacted>");
        return true;
    }

    #endregion
}
