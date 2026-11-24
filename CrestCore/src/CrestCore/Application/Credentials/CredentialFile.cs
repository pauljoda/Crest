using System.Diagnostics.CodeAnalysis;
using System.Text;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A password file as the core reads it: its format, the passwords its rows
/// hold, each with any name, note and one-time code link, and the rows it
/// leaves out. The first row names the columns; blank rows are skipped, and
/// the rest count from 2 in the order they appear. A row's site may leave out
/// its scheme, which is then HTTPS.
[HoldsSecrets]
internal sealed record CredentialFile(CredentialFileFormat Format, IReadOnlyList<ImportedCredential> Credentials,
    IReadOnlyList<CredentialRowRejection> Rejections) {
    #region Static Variables

    /// The largest file an import reads, in megabytes and in bytes.
    public const int MaximumMegabytes = 16;
    public const int MaximumBytes = MaximumMegabytes * 1024 * 1024;
    /// The most credential rows a file may hold.
    public const int MaximumRows = 10_000;
    /// The most columns a row may hold.
    public const int MaximumColumns = 64;
    /// The most characters a field may hold.
    public const int MaximumFieldCharacters = 65_536;

    private static readonly CsvReader Reader = new(new CsvLimits(MaximumRows + 1, MaximumColumns, MaximumFieldCharacters));

    #endregion

    #region Actions - Reading

    /// The file `document` holds. Throws `Rejected` with
    /// `InvalidCredentialFile` for one that cannot import at all.
    public static CredentialFile Read(byte[] document) {
        ArgumentNullException.ThrowIfNull(document);
        if (document.Length > MaximumBytes) throw Invalid(CredentialFileFlaw.TooLarge);
        string text;
        try {
            text = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true).GetString(document);
        } catch (DecoderFallbackException) {
            throw Invalid(CredentialFileFlaw.NotText);
        }
        IReadOnlyList<IReadOnlyList<string>> rows;
        try {
            rows = Reader.Read(text);
        } catch (CsvException error) {
            throw Invalid(CredentialFileFlaw.Answering(error.Fault));
        }
        rows = [.. rows.Where(row => row.Any(field => !string.IsNullOrWhiteSpace(field)))];
        if (rows.Count == 0) throw Invalid(CredentialFileFlaw.Empty);
        var headers = rows[0].Select(CredentialFileColumn.Normalized).ToArray();
        int site = CredentialFileColumn.Site.Index(headers)!.Value;
        int username = CredentialFileColumn.Username.Index(headers)!.Value;
        int password = CredentialFileColumn.Password.Index(headers)!.Value;
        int? name = CredentialFileColumn.DisplayName.Index(headers);
        int? note = CredentialFileColumn.Note.Index(headers);
        int? code = CredentialFileColumn.OneTimeCode.Index(headers);
        var format = CredentialFileFormat.Detected(headers.ToHashSet(StringComparer.Ordinal));
        if (rows.Count - 1 > MaximumRows) throw Invalid(CredentialFileFlaw.TooManyRows);
        if (rows.Count == 1) throw Invalid(CredentialFileFlaw.NoRows);

        var credentials = new List<ImportedCredential>(rows.Count - 1);
        var rejections = new List<CredentialRowRejection>();
        for (int index = 1; index < rows.Count; index++) {
            var row = rows[index];
            int rowNumber = index + 1;
            if (row.Count > headers.Length) {
                rejections.Add(new(rowNumber, CredentialRowFlaw.MalformedRow));
                continue;
            }
            string Field(int column) => column < row.Count ? row[column] : "";
            string? Optional(int? column) => column is { } at && Field(at) is { Length: > 0 } value ? value : null;
            if (!TryOrigin(Field(site), out var origin, out var flaw)) {
                rejections.Add(new(rowNumber, flaw));
                continue;
            }
            string secret = Field(password);
            if (secret.Length == 0) {
                rejections.Add(new(rowNumber, CredentialRowFlaw.EmptyPassword));
                continue;
            }
            string? link = Optional(code)?.Trim() is { Length: > 0 } trimmed ? trimmed : null;
            credentials.Add(new(rowNumber, Optional(name), origin, Field(username), secret, Optional(note), link));
        }
        return new(format, credentials, rejections);
    }

    /// The HTTP(S) origin `site` names once trimmed, with HTTPS for a site
    /// written without a scheme, or the flaw that keeps it from naming one. A
    /// host in brackets is kept as spelled, so an escaped zone ID is refused
    /// rather than read as part of the address, and it must be an IPv6
    /// address; a host ending in a number must be an IPv4 address. An IP
    /// address is spelled as a page's origin spells it, so the password fills
    /// there and merges with one saved for the same address, and a name must
    /// meet IDNA's bidi rule, as the platforms' URL parsers require.
    public static bool TryOrigin(string site, [NotNullWhen(true)] out CredentialOrigin? origin,
        [NotNullWhen(false)] out CredentialRowFlaw? flaw) {
        ArgumentNullException.ThrowIfNull(site);
        string trimmed = site.Trim();
        if (trimmed.Length == 0) return Refuse(CredentialRowFlaw.NoSite, out origin, out flaw);
        int separator = trimmed.IndexOf("://", StringComparison.Ordinal);
        bool hasScheme = separator > 0 && IsScheme(trimmed[..separator]);
        if (hasScheme && WebScheme.Spelled(trimmed[..separator]) is null) return Refuse(CredentialRowFlaw.NotWebAddress, out origin, out flaw);
        if (ImportAddress.Read(hasScheme ? trimmed : $"https://{trimmed}") is not { } address
            || WebScheme.Named(address.Scheme) is not { } scheme)
            return Refuse(CredentialRowFlaw.InvalidOrigin, out origin, out flaw);

        string? literal = address.IPLiteral?.ToLowerInvariant();
        string? host = CredentialOrigin.CanonicalHost(literal ?? address.Host.ToLowerInvariant());
        if (literal is not null && (host is null || !literal.Contains(':', StringComparison.Ordinal)))
            return Refuse(IsScoped(literal) ? CredentialRowFlaw.ZoneIdentifier : CredentialRowFlaw.NotIPv6Address, out origin, out flaw);
        if (host is null) return Refuse(CredentialRowFlaw.NotIPv4Address, out origin, out flaw);
        if (!BidiClass.AllowsHost(host)) return Refuse(CredentialRowFlaw.MixedDirectionName, out origin, out flaw);

        origin = new CredentialOrigin(scheme.Name, host, address.Port ?? scheme.DefaultPort);
        if (origin.Port is < 1 or > 65_535) return Refuse(CredentialRowFlaw.InvalidPort, out origin, out flaw);
        if (!origin.IsValid) return Refuse(CredentialRowFlaw.InvalidOrigin, out origin, out flaw);
        flaw = null;
        return true;
    }

    /// False, with no origin, for a site `reason` keeps out.
    private static bool Refuse(CredentialRowFlaw reason, out CredentialOrigin? origin, out CredentialRowFlaw flaw) {
        (origin, flaw) = (null, reason);
        return false;
    }

    /// Whether `text` is spelled as a scheme: a letter, then letters, digits,
    /// `+`, `-` or `.`.
    private static bool IsScheme(string text) =>
        char.IsAsciiLetter(text[0]) && text.All(character => char.IsAsciiLetterOrDigit(character) || character is '+' or '-' or '.');

    /// Whether `literal`, a host in brackets, is an IPv6 address followed by a
    /// zone ID, escaped or not.
    private static bool IsScoped(string literal) {
        int zone = literal.IndexOf('%', StringComparison.Ordinal);
        return zone > 0 && literal[..zone].Contains(':', StringComparison.Ordinal)
            && CredentialOrigin.CanonicalHost(literal[..zone]) is not null;
    }

    private static Rejected Invalid(CredentialFileFlaw flaw) => new(new InvalidCredentialFile(flaw));

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CredentialFile { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Format = {Format.Name}, Credentials = {Credentials.Count}, Rejections = {Rejections.Count}");
        return true;
    }

    #endregion
}
