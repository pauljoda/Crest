namespace CrestCore.Contracts;

/// The network that issued a payment card, known from the first digits of its
/// number: the ranges of those digits it holds, the lengths its numbers come
/// in, the digits of its security code and how its numbers are grouped when
/// shown. Where ranges of several networks hold a number, the longest range
/// names its network, so a Discover card beginning 622126 is not taken for a
/// UnionPay one. `Unknown` stands for a number no range holds. A network
/// travels as its index in `All`, so `All` is append-only.
public sealed class CardNetwork {
    #region Static Variables

    public static readonly CardNetwork Visa = new(name: "visa", displayName: "Visa", prefixes: ["4"], lengths: [13, 16, 19]);

    public static readonly CardNetwork Mastercard = new(name: "mastercard", displayName: "Mastercard",
        prefixes: ["51-55", "2221-2720"], lengths: [16]);

    public static readonly CardNetwork AmericanExpress = new(name: "americanExpress", displayName: "American Express",
        prefixes: ["34", "37"], lengths: [15], securityCodeLength: 4, grouping: [4, 6, 5]);

    public static readonly CardNetwork Discover = new(name: "discover", displayName: "Discover",
        prefixes: ["6011", "644-649", "65", "622126-622925"], lengths: [16, 17, 18, 19]);

    public static readonly CardNetwork DinersClub = new(name: "dinersClub", displayName: "Diners Club",
        prefixes: ["300-305", "3095", "36", "38-39"], lengths: [14, 15, 16, 17, 18, 19], grouping: [4, 6, 4]);

    public static readonly CardNetwork Jcb = new(name: "jcb", displayName: "JCB", prefixes: ["3528-3589"], lengths: [16, 17, 18, 19]);

    public static readonly CardNetwork UnionPay = new(name: "unionPay", displayName: "UnionPay", prefixes: ["62", "81"],
        lengths: [16, 17, 18, 19]);

    public static readonly CardNetwork Maestro = new(name: "maestro", displayName: "Maestro",
        prefixes: ["50", "56-61", "63", "66-69"], lengths: [12, 13, 14, 15, 16, 17, 18, 19]);

    public static readonly CardNetwork Mir = new(name: "mir", displayName: "Mir", prefixes: ["2200-2204"], lengths: [16, 17, 18, 19]);

    public static readonly CardNetwork Unknown = new(name: "unknown", displayName: "Card", prefixes: [],
        lengths: [12, 13, 14, 15, 16, 17, 18, 19]);

    public static IReadOnlyList<CardNetwork> All { get; } =
        [Visa, Mastercard, AmericanExpress, Discover, DinersClub, Jcb, UnionPay, Maestro, Mir, Unknown];

    #endregion

    #region Variables

    public string Name { get; }

    /// The network's name as the person reads it beside a saved card.
    [Localized]
    public string DisplayName { get; }

    public string DisplayNameComment { get; } =
        "The name of a payment card network, shown beside a saved card. Keep brand names as they are; “Card” names a card of no known network.";

    /// The numbers of digits its card numbers come in, shortest first.
    public IReadOnlyList<int> Lengths { get; }

    /// The digits of its cards' security code.
    public int SecurityCodeLength { get; }

    /// The sizes of the groups a number of `Lengths`' sum of digits is shown
    /// in, such as 4, 6 and 5 for American Express. A number of another length
    /// is shown in groups of four.
    public IReadOnlyList<int> Grouping { get; }

    /// The ranges of leading digits that name the network, each as its lowest
    /// and highest digits of one length.
    private readonly IReadOnlyList<(string Lowest, string Highest)> ranges;

    #endregion

    #region Constructors

    /// `prefixes` spell each range as `low-high`, or one prefix alone.
    private CardNetwork(string name, string displayName, IReadOnlyList<string> prefixes, IReadOnlyList<int> lengths,
        int securityCodeLength = 3, IReadOnlyList<int>? grouping = null) {
        Name = name;
        DisplayName = displayName;
        Lengths = lengths;
        SecurityCodeLength = securityCodeLength;
        Grouping = grouping ?? [4, 4, 4, 4];
        ranges = [.. prefixes.Select(prefix => prefix.Split('-') is [var lowest, var highest] ? (lowest, highest) : (prefix, prefix))];
    }

    #endregion

    #region Actions - Lookup

    public static CardNetwork? Named(string? name) => All.FirstOrDefault(network => network.Name == name);

    /// The network of the card number `digits`: the one whose longest range
    /// holds its leading digits, or `Unknown`.
    internal static CardNetwork Of(string digits) {
        ArgumentNullException.ThrowIfNull(digits);
        return All.Select(network => (Network: network, Digits: network.MatchedDigits(digits)))
            .Where(match => match.Digits > 0).OrderByDescending(match => match.Digits).Select(match => match.Network)
            .FirstOrDefault() ?? Unknown;
    }

    /// The length of the longest of the network's ranges that holds the
    /// leading digits of `digits`, or 0 when none does.
    private int MatchedDigits(string digits) => ranges
        .Where(range => digits.Length >= range.Lowest.Length && Holds(range, digits[..range.Lowest.Length]))
        .Select(range => range.Lowest.Length).DefaultIfEmpty(0).Max();

    private static bool Holds((string Lowest, string Highest) range, string leading) =>
        string.CompareOrdinal(leading, range.Lowest) >= 0 && string.CompareOrdinal(leading, range.Highest) <= 0;

    #endregion

    #region Actions - Numbers

    /// Whether a number of `length` digits is one of the network's.
    internal bool Allows(int length) => Lengths.Contains(length);

    /// `digits` in the groups the network shows them in, each separated by
    /// `separator`.
    internal string Grouped(string digits, string separator) {
        ArgumentNullException.ThrowIfNull(digits);
        IReadOnlyList<int> sizes = Grouping.Sum() == digits.Length ? Grouping : [.. Enumerable.Repeat(4, (digits.Length + 3) / 4)];
        var groups = new List<string>();
        int start = 0;
        foreach (int size in sizes) {
            if (start >= digits.Length) break;
            groups.Add(digits.Substring(start, Math.Min(size, digits.Length - start)));
            start += size;
        }
        return string.Join(separator, groups);
    }

    #endregion
}
