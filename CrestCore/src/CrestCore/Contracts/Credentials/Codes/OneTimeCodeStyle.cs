using CrestCore.Domain;

namespace CrestCore.Contracts;

/// How a one-time code is written: RFC 6238's numeric code of 6 to 8 digits,
/// made with any algorithm every 10 to 300 seconds, or Steam's code of 5
/// characters from SHA-1 every 30 seconds. Both take RFC 4226's truncation of
/// the HMAC and write it in their own alphabet: the numeric code from its
/// highest place, as a number is written, and Steam's from its lowest. A
/// member travels as its index in `All`, so `All` is append-only.
public sealed class OneTimeCodeStyle {
    #region Static Variables

    public static readonly OneTimeCodeStyle Numeric = new(name: "numeric", alphabet: "0123456789", lowestPlaceFirst: false,
        digits: new(6, 8, 6), periods: new(10, 300, 30), algorithms: OneTimeCodeAlgorithm.All);

    public static readonly OneTimeCodeStyle Steam = new(name: "steam", alphabet: "23456789BCDFGHJKMNPQRTVWXY", lowestPlaceFirst: true,
        digits: new(5, 5, 5), periods: new(30, 30, 30), algorithms: [OneTimeCodeAlgorithm.Sha1], encoder: "steam", issuer: "Steam");

    public static IReadOnlyList<OneTimeCodeStyle> All { get; } = [Numeric, Steam];

    #endregion

    #region Variables

    public string Name { get; }

    /// How many characters a code may have.
    internal OneTimeCodeLimit Digits { get; }

    /// How many seconds a code may last.
    internal OneTimeCodeLimit Periods { get; }

    /// How an otpauth link's `encoder` parameter names the style, which is
    /// also its own links' scheme and an otpauth link's type for it, or null
    /// for the style a link that names none means.
    internal string? Encoder { get; }

    /// The issuer a setup of the style takes when it names none.
    internal string Issuer { get; }

    /// The algorithm a setup of the style takes when it names none.
    internal OneTimeCodeAlgorithm DefaultAlgorithm => algorithms[0];

    /// The algorithms the style is made with, the default first.
    private readonly IReadOnlyList<OneTimeCodeAlgorithm> algorithms;

    /// The characters a code is written with, the one for zero first.
    private readonly string alphabet;

    /// Whether a code is written from its lowest place, not its highest.
    private readonly bool lowestPlaceFirst;

    #endregion

    #region Constructors

    private OneTimeCodeStyle(string name, string alphabet, bool lowestPlaceFirst, OneTimeCodeLimit digits, OneTimeCodeLimit periods,
        IReadOnlyList<OneTimeCodeAlgorithm> algorithms, string? encoder = null, string issuer = "") {
        Name = name;
        Digits = digits;
        Periods = periods;
        Encoder = encoder;
        Issuer = issuer;
        this.algorithms = algorithms;
        this.alphabet = alphabet;
        this.lowestPlaceFirst = lowestPlaceFirst;
    }

    #endregion

    #region Actions - Lookup

    public static OneTimeCodeStyle? Named(string? name) => All.FirstOrDefault(style => style.Name == name);

    /// The style an otpauth link's `encoder` parameter, or a link's scheme or
    /// type, names: the numeric one when an encoder names none, or null when
    /// it names one Crest doesn't make.
    internal static OneTimeCodeStyle? Encoded(string? encoder) =>
        All.FirstOrDefault(style => string.Equals(style.Encoder, encoder, StringComparison.OrdinalIgnoreCase));

    #endregion

    #region Actions - Reading

    /// The algorithm a link's `spelling` names for a code of this style: the
    /// default when it names none or the style is made with only one, and
    /// otherwise the one it names, or null when the style isn't made with it.
    internal OneTimeCodeAlgorithm? Algorithm(string? spelling) {
        if (spelling is null || algorithms.Count == 1) return DefaultAlgorithm;
        return OneTimeCodeAlgorithm.Spelled(spelling) is { } named && algorithms.Contains(named) ? named : null;
    }

    /// Why a code of this style can't be made with `algorithm`, `digits`
    /// characters long and lasting `period` seconds, or null when it can.
    internal CodeSetupRefusal? Refusal(OneTimeCodeAlgorithm algorithm, int digits, int period) {
        if (!algorithms.Contains(algorithm)) return CodeSetupRefusal.UnsupportedAlgorithm;
        if (!Digits.Admits(digits)) return CodeSetupRefusal.InvalidDigits;
        return Periods.Admits(period) ? null : CodeSetupRefusal.InvalidPeriod;
    }

    #endregion

    #region Actions - Writing

    /// `value`, the truncated HMAC, written as a code of `length` characters:
    /// its lowest `length` places in the style's alphabet.
    internal string Write(uint value, int length) {
        var characters = new char[length];
        uint radix = (uint)alphabet.Length;
        for (int place = 0; place < length; place++) {
            characters[lowestPlaceFirst ? place : length - 1 - place] = alphabet[(int)(value % radix)];
            value /= radix;
        }
        return new string(characters);
    }

    #endregion
}
