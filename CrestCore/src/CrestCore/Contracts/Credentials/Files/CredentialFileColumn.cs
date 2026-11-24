namespace CrestCore.Contracts;

/// A column a password file names under one of several headers, as the
/// programs that write such files spell it, compared once normalized. A
/// required column the file lacks, or names twice, keeps the file from
/// importing; an optional column's first matching header wins. A column
/// travels as its index in `All`, so `All` is append-only.
public sealed class CredentialFileColumn {
    #region Static Variables

    public static readonly CredentialFileColumn Site = new(name: "site", title: "Site", headers: ["url", "origin", "website", "login_uri"],
        missing: CredentialFileFlaw.NoSiteColumn, repeated: CredentialFileFlaw.SeveralSiteColumns);
    public static readonly CredentialFileColumn Username = new(name: "username", title: "Username",
        headers: ["username", "user", "login", "email", "login_username"], missing: CredentialFileFlaw.NoUsernameColumn,
        repeated: CredentialFileFlaw.SeveralUsernameColumns);
    public static readonly CredentialFileColumn Password = new(name: "password", title: "Password",
        headers: ["password", "pass", "login_password"], missing: CredentialFileFlaw.NoPasswordColumn,
        repeated: CredentialFileFlaw.SeveralPasswordColumns);
    /// The name a row gives its account.
    public static readonly CredentialFileColumn DisplayName = new(name: "displayName", title: "Name", headers: ["name", "title"],
        missing: null, repeated: null);
    /// The note a row keeps beside its password.
    public static readonly CredentialFileColumn Note = new(name: "note", title: "Notes", headers: ["note", "notes", "comments"],
        missing: null, repeated: null);
    /// The `otpauth://` link a row's one-time codes come from.
    public static readonly CredentialFileColumn OneTimeCode = new(name: "oneTimeCode", title: "One-time code",
        headers: ["otpauth", "otp_auth", "totp", "otp", "one_time_code", "one_time_password", "login_totp"], missing: null, repeated: null);

    public static IReadOnlyList<CredentialFileColumn> All { get; } = [Site, Username, Password, DisplayName, Note, OneTimeCode];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the person knows the column as.
    [Localized]
    public string Title { get; }

    private readonly IReadOnlySet<string> headers;
    /// Why a file lacking the column cannot import, or null for a column a
    /// file may leave out.
    private readonly CredentialFileFlaw? missing;
    /// Why a file naming the column twice cannot import, or null for one
    /// whose first header wins.
    private readonly CredentialFileFlaw? repeated;

    #endregion

    #region Constructors

    private CredentialFileColumn(string name, string title, IReadOnlyList<string> headers, CredentialFileFlaw? missing,
        CredentialFileFlaw? repeated) {
        Name = name;
        Title = title;
        this.headers = headers.ToHashSet(StringComparer.Ordinal);
        this.missing = missing;
        this.repeated = repeated;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialFileColumn? Named(string? name) => All.FirstOrDefault(column => column.Name == name);

    #endregion

    #region Actions - Headers

    /// Where the column is among `normalized`, a file's headers as `Normalized`
    /// spells them, or null when an optional column is absent. Throws
    /// `Rejected` with `InvalidCredentialFile` for a required column that is
    /// absent, or one named twice.
    internal int? Index(IReadOnlyList<string> normalized) {
        ArgumentNullException.ThrowIfNull(normalized);
        var matches = Enumerable.Range(0, normalized.Count).Where(index => headers.Contains(normalized[index])).ToArray();
        if (matches.Length == 0)
            return missing is { } flaw ? throw new Rejected(new InvalidCredentialFile(flaw)) : null;
        if (matches.Length > 1 && repeated is { } ambiguous) throw new Rejected(new InvalidCredentialFile(ambiguous));
        return matches[0];
    }

    /// `header` as columns are compared: trimmed of spaces, line breaks and
    /// byte-order marks, in lowercase, with hyphens and spaces read as
    /// underscores.
    internal static string Normalized(string header) {
        ArgumentNullException.ThrowIfNull(header);
        int start = 0, end = header.Length;
        while (start < end && IsTrimmed(header[start])) start++;
        while (end > start && IsTrimmed(header[end - 1])) end--;
        return header[start..end].ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }

    private static bool IsTrimmed(char character) => char.IsWhiteSpace(character) || character == '﻿';

    #endregion
}
