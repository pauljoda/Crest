using System.Text;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What the card number `Number` says: its network, its last four digits and
/// whether it is complete. `Number` may hold spaces and dashes between its
/// digits, as a person types it. It reads nothing the app holds.
[HoldsSecrets]
public sealed record CardDetails(string Number) : StandaloneQuery<CardSummary> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override CardSummary Answer(StandaloneContext context) =>
        CardNumber.Read(Number) is { } number ? new(number.Network, number.LastFour, number.IsValid) : new(CardNetwork.Unknown, "", false);

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CardDetails { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    protected override bool PrintMembers(StringBuilder builder) {
        builder.Append("Number = <redacted>");
        return true;
    }

    #endregion
}
