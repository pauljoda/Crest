using CrestCore.Contracts;

namespace CrestCore.Application;

/// A rule of the person's own filters that hides what a selector matches on
/// one host, as Block Element writes it: `host##selector`, the lists' syntax
/// for a site's hiding rule.
internal sealed record ElementRule(string Host, string Selector) {
    #region Variables

    /// The rule as a line of the person's filters.
    public string Text => $"{Host}##{Selector}";

    #endregion

    #region Actions - Rules

    /// The longest selector a rule takes from a page.
    public const int MaximumSelectorLength = 1024;

    /// The rule that hides `selector` on the host of the page at `pageUrl`.
    /// Refused for a page that is not on the web, or for a selector that could
    /// be more than a hiding rule for that host: one with a control character
    /// or line separator, which could start a rule of its own, one a filter
    /// list reads as a scriptlet or an HTML filter, another rule's separator,
    /// or one longer than a rule takes.
    public static ElementRule For(string pageUrl, string selector) {
        var trimmed = selector?.Trim() ?? "";
        if (HostOf(pageUrl) is not { } host || trimmed.Length == 0 || trimmed.Length > MaximumSelectorLength
            || trimmed.Any(character => char.IsControl(character) || character is '\u2028' or '\u2029')
            || trimmed.StartsWith("+js(", StringComparison.Ordinal) || trimmed.StartsWith('^')
            || trimmed.Contains("##") || trimmed.Contains("#@#") || trimmed.Contains("#?#") || trimmed.Contains("#$#"))
            throw new Rejected(new ElementSelectorInvalid(selector?.Length > 200 ? selector[..200] : selector ?? ""));
        return new(host, trimmed);
    }

    /// The host whose rules a page at `pageUrl` follows, or null for a page
    /// that is not on the web.
    public static string? HostOf(string pageUrl) => new WebAddress(pageUrl ?? "").Origin?.Host;

    /// Whether `line` of the person's filters hides something on `host`.
    public static bool Hides(string line, string host) =>
        line.Trim().StartsWith(host + "##", StringComparison.OrdinalIgnoreCase);

    #endregion
}
