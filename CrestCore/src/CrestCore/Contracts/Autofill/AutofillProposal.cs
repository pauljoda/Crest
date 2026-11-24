using System.Text;

namespace CrestCore.Contracts;

/// What a sent form offers to keep: the address and the card the person
/// entered, each null when the form held none complete enough to keep. A
/// proposed record's `Id` is empty, and so is its `Label` or `Nickname`; the
/// platform identifies and names a record it saves. A proposed card never
/// holds a security code.
[HoldsSecrets]
public sealed record AutofillProposal(AddressRecord? Address, CardRecord? Card) {
    #region Static Variables

    /// A form that offers nothing to keep.
    internal static AutofillProposal Nothing { get; } = new(null, null);

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("AutofillProposal { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name nothing of the address or card.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Address = {(Address is null ? "none" : "<redacted>")}, Card = {(Card is null ? "none" : "<redacted>")}");
        return true;
    }

    #endregion
}
