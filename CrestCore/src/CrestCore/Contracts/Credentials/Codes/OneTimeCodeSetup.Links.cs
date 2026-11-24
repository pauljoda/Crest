using System.Globalization;
using System.Text;

namespace CrestCore.Contracts;

public sealed partial record OneTimeCodeSetup {
    #region Static Variables

    /// The longest text Crest reads as a setup.
    internal const int MaximumTextLength = 2_048;

    private const string SchemeSeparator = "://";
    private const string LinkScheme = "otpauth";
    private const string TimeBasedType = "totp";
    private const string CounterBasedType = "hotp";

    private const string SecretParameter = "secret";
    private const string IssuerParameter = "issuer";
    private const string AlgorithmParameter = "algorithm";
    private const string DigitsParameter = "digits";
    private const string PeriodParameter = "period";
    private const string EncoderParameter = "encoder";

    #endregion

    #region Actions - Reading

    /// What `text`, without the whitespace around it, sets up: an otpauth
    /// link to time-based codes, `otpauth://totp/Issuer:Account?secret=…`,
    /// whose percent-encoded label may put a space after the colon and whose
    /// `issuer` parameter wins over the label's; a link of a style with a
    /// scheme of its own, such as `steam://KEY`, or `otpauth://steam/…`; or a
    /// bare base32 key in any case, with spaces, hyphens or padding.
    internal static ParsedCodeSetup Read(string text) {
        ArgumentNullException.ThrowIfNull(text);
        string trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed.Length > MaximumTextLength) return Refused(CodeSetupRefusal.NotASetup);
        int separator = trimmed.IndexOf(SchemeSeparator, StringComparison.Ordinal);
        if (separator < 0) return ReadKey(trimmed);
        string scheme = trimmed[..separator];
        string rest = trimmed[(separator + SchemeSeparator.Length)..];
        if (scheme.Equals(LinkScheme, StringComparison.OrdinalIgnoreCase)) return ReadLink(rest);
        if (OneTimeCodeStyle.Encoded(scheme) is not { } style) return Refused(CodeSetupRefusal.NotASetup);
        string key = Uri.UnescapeDataString(rest.Split(['?', '#'])[0].TrimEnd('/'));
        return Checked(new(Canonical(key), style.Issuer, "", style.DefaultAlgorithm, style.Digits.Default, style.Periods.Default, style));
    }

    /// A bare key: letters and digits, with any spaces, hyphens and padding.
    private static ParsedCodeSetup ReadKey(string text) {
        if (!text.All(character => char.IsAsciiLetterOrDigit(character) || char.IsWhiteSpace(character) || character is '-' or '='))
            return Refused(CodeSetupRefusal.NotASetup);
        var style = OneTimeCodeStyle.Numeric;
        return Checked(new(Canonical(text), style.Issuer, "", style.DefaultAlgorithm, style.Digits.Default, style.Periods.Default, style));
    }

    /// An otpauth link, after its scheme. A parameter the link leaves out or
    /// leaves empty takes the style's default, and one the style allows only
    /// one value for is ignored.
    private static ParsedCodeSetup ReadLink(string link) {
        string whole = link.Split('#')[0];
        int question = whole.IndexOf('?', StringComparison.Ordinal);
        string path = question < 0 ? whole : whole[..question];
        var parameters = Parameters(question < 0 ? "" : whole[(question + 1)..]);
        int slash = path.IndexOf('/', StringComparison.Ordinal);
        string type = slash < 0 ? path : path[..slash];
        string? named = parameters.GetValueOrDefault(IssuerParameter);
        var (labeled, account) = Label(Uri.UnescapeDataString(slash < 0 ? "" : path[(slash + 1)..]), named);
        string issuer = named ?? labeled;
        if (type.Equals(CounterBasedType, StringComparison.OrdinalIgnoreCase)) return Refused(CodeSetupRefusal.CounterBased);
        OneTimeCodeStyle? style;
        if (type.Equals(TimeBasedType, StringComparison.OrdinalIgnoreCase)) {
            style = OneTimeCodeStyle.Encoded(parameters.GetValueOrDefault(EncoderParameter));
            if (style is null) return Refused(CodeSetupRefusal.UnsupportedAlgorithm);
        } else {
            style = OneTimeCodeStyle.Encoded(type);
            if (style is null) return Refused(CodeSetupRefusal.NotASetup);
        }
        if (!parameters.TryGetValue(SecretParameter, out string? secret)) return Refused(CodeSetupRefusal.InvalidSecret);
        string canonical = Canonical(secret);
        if (SecretRefusal(canonical) is { } refusal) return Refused(refusal);
        if (style.Algorithm(parameters.GetValueOrDefault(AlgorithmParameter)) is not { } algorithm)
            return Refused(CodeSetupRefusal.UnsupportedAlgorithm);
        if (style.Digits.Read(parameters.GetValueOrDefault(DigitsParameter)) is not int digits) return Refused(CodeSetupRefusal.InvalidDigits);
        if (style.Periods.Read(parameters.GetValueOrDefault(PeriodParameter)) is not int period) return Refused(CodeSetupRefusal.InvalidPeriod);
        return Checked(new(canonical, issuer.Length > 0 ? issuer : style.Issuer, account, algorithm, digits, period, style));
    }

    /// The query's parameters by name, in any case, each percent-decoded with
    /// `+` read as a space and trimmed. The first non-empty value of a name
    /// counts.
    private static Dictionary<string, string> Parameters(string query) {
        var parameters = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string pair in query.Split('&', StringSplitOptions.RemoveEmptyEntries)) {
            int equals = pair.IndexOf('=', StringComparison.Ordinal);
            if (equals <= 0) continue;
            string value = Uri.UnescapeDataString(pair[(equals + 1)..].Replace('+', ' ')).Trim();
            if (value.Length > 0) parameters.TryAdd(Uri.UnescapeDataString(pair[..equals]).Trim(), value);
        }
        return parameters;
    }

    /// The issuer and account a decoded label names: `Issuer:Account`, with
    /// or without a space after the colon, or the account alone. A label that
    /// begins with the link's `issuer` parameter and a colon names the
    /// account after them, so an issuer may hold a colon of its own.
    private static (string Issuer, string Account) Label(string label, string? issuer) {
        if (issuer is not null && label.StartsWith($"{issuer}:", StringComparison.Ordinal))
            return (issuer, label[(issuer.Length + 1)..].Trim());
        int colon = label.IndexOf(':', StringComparison.Ordinal);
        return colon < 0 ? ("", label.Trim()) : (label[..colon].Trim(), label[(colon + 1)..].Trim());
    }

    /// `text` as canonical base32 would spell it: in uppercase, without
    /// whitespace, hyphens or the padding at its end. Whether what is left is
    /// base32 is the setup's to say.
    private static string Canonical(string text) {
        var canonical = new StringBuilder(text.Length);
        foreach (char character in text)
            if (!char.IsWhiteSpace(character) && character != '-') canonical.Append(char.ToUpperInvariant(character));
        return canonical.ToString().TrimEnd('=');
    }

    private static ParsedCodeSetup Checked(OneTimeCodeSetup setup) =>
        setup.Refusal is { } refusal ? Refused(refusal) : new(setup, null);

    private static ParsedCodeSetup Refused(CodeSetupRefusal refusal) => new(null, refusal);

    #endregion

    #region Actions - Writing

    /// The setup's canonical otpauth link, which reads back as an equal
    /// setup: `otpauth://totp/Issuer:Account` with the label percent-encoded,
    /// then its secret, issuer, algorithm, digits and period, and the encoder
    /// of a style that has one. A label without an issuer is the account
    /// alone, after a colon only when the account holds one.
    internal CodeSetupLink Link() {
        if (Refusal is { } refusal) throw new Rejected(new InvalidCodeSetup(refusal));
        string account = Uri.EscapeDataString(Account);
        string label = Issuer.Length > 0 || Account.Contains(':', StringComparison.Ordinal)
            ? $"{Uri.EscapeDataString(Issuer)}:{account}"
            : account;
        var link = new StringBuilder($"{LinkScheme}{SchemeSeparator}{TimeBasedType}/{label}?{SecretParameter}={Secret}");
        if (Issuer.Length > 0) link.Append(CultureInfo.InvariantCulture, $"&{IssuerParameter}={Uri.EscapeDataString(Issuer)}");
        link.Append(CultureInfo.InvariantCulture,
            $"&{AlgorithmParameter}={Algorithm.Name}&{DigitsParameter}={Digits}&{PeriodParameter}={Period}");
        if (Style.Encoder is { } encoder) link.Append(CultureInfo.InvariantCulture, $"&{EncoderParameter}={encoder}");
        return new(link.ToString());
    }

    #endregion
}
