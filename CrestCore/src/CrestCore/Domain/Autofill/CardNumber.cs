using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A payment card's number as its digits: the network its leading digits
/// name, its last four digits, and whether it is complete, of a length its
/// network issues and passing the Luhn check every card number carries.
[HoldsSecrets]
internal sealed class CardNumber {
    #region Static Variables

    /// The most characters of text a number is read from.
    private const int MaximumCharacters = 64;

    #endregion

    #region Variables

    public string Digits { get; }

    public CardNetwork Network { get; }

    public string LastFour => Digits.Length > 4 ? Digits[^4..] : Digits;

    /// Whether the number is of a length its network issues and passes the
    /// Luhn check.
    public bool IsValid => Digits.Length >= CardRecord.MinimumNumberDigits && Network.Allows(Digits.Length) && PassesLuhn;

    /// Whether the number's check digit is right: doubling every second digit
    /// from the right, the digits sum to a multiple of ten.
    private bool PassesLuhn {
        get {
            int sum = 0;
            for (int place = 0; place < Digits.Length; place++) {
                int digit = Digits[Digits.Length - 1 - place] - '0';
                if (place % 2 == 1) digit = digit * 2 > 9 ? digit * 2 - 9 : digit * 2;
                sum += digit;
            }
            return sum % 10 == 0;
        }
    }

    #endregion

    #region Constructors

    private CardNumber(string digits) {
        Digits = digits;
        Network = CardNetwork.Of(digits);
    }

    #endregion

    #region Actions - Reading

    /// The number `text` spells, as digits optionally separated by spaces or
    /// dashes, or null when it holds anything else or more digits than a card
    /// number has.
    public static CardNumber? Read(string? text) {
        if (string.IsNullOrWhiteSpace(text) || text.Length > MaximumCharacters) return null;
        var digits = text.Where(character => character is not (' ' or '-')).ToArray();
        if (digits.Length == 0 || digits.Length > CardRecord.MaximumNumberDigits || !digits.All(char.IsAsciiDigit)) return null;
        return new(new string(digits));
    }

    /// The number shown in its network's groups, separated by `separator`.
    public string Grouped(string separator) => Network.Grouped(Digits, separator);

    #endregion

    #region Actions - Text

    public override string ToString() => $"CardNumber {{ Network = {Network.Name}, Digits = <redacted> }}";

    #endregion
}
