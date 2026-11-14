using System.Collections.Concurrent;
using System.Text.RegularExpressions;

namespace CrestCore.Domain;

/// A regular expression a link filter spells, or translates its pattern to.
/// It is built the first time a filter tests something against it, and
/// shared by every filter that spells it alike, so reading a list builds
/// none. One that does not read matches nothing, and one that takes longer
/// than `MatchTimeout` on a text does not match it.
internal sealed class FilterExpression {
    #region Static Variables

    /// The longest an expression may take on one text: a list's expression
    /// that backtracks without end matches nothing.
    private static readonly TimeSpan MatchTimeout = TimeSpan.FromMilliseconds(50);

    /// Every expression built so far, by its text and whether it minds
    /// letter case; null for one that does not read.
    private static readonly ConcurrentDictionary<(string Text, bool MatchCase), Regex?> Built = new();

    #endregion

    #region Variables

    private readonly string text;
    private readonly bool matchCase;

    /// Whether the expression reads as one.
    public bool IsReadable => Expression() is not null;

    #endregion

    #region Constructors

    public FilterExpression(string text, bool matchCase) {
        ArgumentNullException.ThrowIfNull(text);
        this.text = text;
        this.matchCase = matchCase;
    }

    #endregion

    #region Actions - Matching

    /// Whether the expression matches `input` from `start`, where `\G`
    /// anchors it.
    public bool Matches(string input, int start = 0) {
        ArgumentNullException.ThrowIfNull(input);
        if (Expression() is not { } expression) return false;
        try {
            return expression.Match(input, start).Success;
        } catch (RegexMatchTimeoutException) {
            return false;
        }
    }

    private Regex? Expression() => Built.GetOrAdd((text, matchCase), static key => {
        try {
            return new Regex(key.Text, RegexOptions.CultureInvariant | (key.MatchCase ? RegexOptions.None : RegexOptions.IgnoreCase),
                MatchTimeout);
        } catch (ArgumentException) {
            return null;
        }
    });

    #endregion
}
