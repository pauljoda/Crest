using System.Text;

namespace CrestCore.Contracts;

/// A payment card a Space keeps for filling forms. `Nickname` is the person's
/// name for it, `Number` its digits alone, `ExpiryMonth` 1 to 12 and
/// `ExpiryYear` four digits. `SecurityCode`, three or four digits, is there
/// only when the person chose to keep it, and `BillingAddressId` names the
/// Space's address the card is billed to, if any. The core keeps none: a
/// question that fills or proposes one carries it and forgets it.
[HoldsSecrets]
public sealed record CardRecord(Guid Id, string Nickname, string Cardholder, string Number, int ExpiryMonth, int ExpiryYear,
    string? SecurityCode, Guid? BillingAddressId) {
    #region Static Variables

    public const int MinimumNumberDigits = 12;

    public const int MaximumNumberDigits = 19;

    public const int MaximumTextLength = 200;

    #endregion

    #region Actions - Validation

    /// This record, or `Rejected` with `InvalidAutofillRecord` when a field
    /// breaks its limits.
    internal CardRecord Validated() {
        if (Nickname.Length > MaximumTextLength || Cardholder.Length > MaximumTextLength
            || Number.Length is < MinimumNumberDigits or > MaximumNumberDigits || !Number.All(char.IsAsciiDigit)
            || ExpiryMonth is < 1 or > 12 || ExpiryYear is < 1000 or > 9999
            || SecurityCode is { } code && (code.Length is < 3 or > 4 || !code.All(char.IsAsciiDigit)))
            throw new Rejected(new InvalidAutofillRecord());
        return this;
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CardRecord { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name nothing of the card.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Id = {Id}, Number = <redacted>, SecurityCode = <redacted>, BillingAddressId = {BillingAddressId}");
        return true;
    }

    #endregion
}
