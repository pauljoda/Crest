using System.Text;
using System.Text.RegularExpressions;

namespace CrestCore.Application;

/// A filter list's text as its maintainers publish it, which reads its own
/// header and resolves its conditional blocks. uBlock Origin's lists wrap rules
/// meant for some platforms in `!#if` … `!#else` … `!#endif`; the engine reads
/// every directive as a comment, so a list goes to it only once the blocks that
/// do not apply are left out.
internal sealed partial class FilterListText {
    #region Variables

    /// The longest interval a list's `Expires` header may ask for, as the
    /// filter-list convention caps it.
    private static readonly TimeSpan LongestExpiry = TimeSpan.FromDays(14);

    public string Text { get; }

    #endregion

    #region Constructors

    public FilterListText(string text) {
        ArgumentNullException.ThrowIfNull(text);
        Text = text;
    }

    #endregion

    #region Actions - Header

    /// The list's lines as the engine reads them: split at line feeds alone,
    /// with a carriage return before one dropped, so no other line separator
    /// can start a rule the engine does not see as one.
    private IEnumerable<string> Lines() {
        foreach (var line in Text.Split('\n'))
            yield return line.EndsWith('\r') ? line[..^1] : line;
    }

    /// How long the list says a copy stays current, from its `! Expires:`
    /// header, or null when it says nothing the convention allows.
    public TimeSpan? Expiry() {
        foreach (var line in Lines()) {
            if (line.Length == 0 || line[0] == '[') continue;
            if (line[0] != '!') break;
            var match = ExpiresHeader().Match(line.ToString());
            if (!match.Success) continue;
            if (!int.TryParse(match.Groups["amount"].Value, System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture, out int amount))
                return null;
            var expiry = match.Groups["unit"].Value.StartsWith('h') ? TimeSpan.FromHours(amount) : TimeSpan.FromDays(amount);
            return amount > 0 && expiry <= LongestExpiry ? expiry : null;
        }
        return null;
    }

    [GeneratedRegex(@"^!\s*Expires:\s*(?<amount>[0-9]{1,3})\s*(?<unit>hours?|days?)\b", RegexOptions.IgnoreCase)]
    private static partial Regex ExpiresHeader();

    /// How many rules the list holds: its lines that are neither empty, a
    /// comment, nor a section header.
    public int RuleCount() {
        int count = 0;
        foreach (var line in Lines()) {
            var rule = line.Trim();
            if (rule.Length > 0 && rule[0] != '!' && rule[0] != '[') count++;
        }
        return count;
    }

    /// What the list calls itself, from its `! Title:` header, or null.
    public string? Title() {
        foreach (var line in Lines()) {
            if (line.Length == 0 || line[0] == '[') continue;
            if (line[0] != '!') break;
            var match = TitleHeader().Match(line.ToString());
            if (match.Success) return match.Groups["title"].Value.Trim() is { Length: > 0 and <= 200 } title ? title : null;
        }
        return null;
    }

    [GeneratedRegex(@"^!\s*Title:\s*(?<title>.+)$", RegexOptions.IgnoreCase)]
    private static partial Regex TitleHeader();

    #endregion

    #region Actions - Conditions

    /// The list with each `!#if` block resolved for a platform where exactly
    /// the tokens in `conditions` hold: a block whose condition fails is left
    /// out, as is the `!#else` half of one that holds. A token no platform names,
    /// such as another blocker's, never holds. An `!#include` is left out too:
    /// the lists Crest downloads arrive with their parts inlined.
    public string Resolved(IReadOnlySet<string> conditions) {
        ArgumentNullException.ThrowIfNull(conditions);
        var resolved = new StringBuilder(Text.Length);
        // Whether each open block's current half applies, and whether every
        // block around it does.
        var blocks = new Stack<(bool Holds, bool Enclosed)>();
        bool applies = true;
        foreach (var line in Lines()) {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("!#if", StringComparison.Ordinal)) {
                bool holds = Condition.Holds(trimmed[4..].ToString(), conditions);
                blocks.Push((holds, applies));
                applies = applies && holds;
            } else if (trimmed.StartsWith("!#else", StringComparison.Ordinal)) {
                if (blocks.TryPop(out var block)) {
                    blocks.Push((!block.Holds, block.Enclosed));
                    applies = block.Enclosed && !block.Holds;
                }
            } else if (trimmed.StartsWith("!#endif", StringComparison.Ordinal)) {
                if (blocks.TryPop(out var block)) applies = block.Enclosed;
            } else if (applies && !trimmed.StartsWith("!#include", StringComparison.Ordinal)) {
                resolved.Append(line).Append('\n');
            }
        }
        return resolved.ToString();
    }

    /// A `!#if` condition: tokens joined by `&&` and `||`, each negated by `!`
    /// and grouped by parentheses, as uBlock Origin writes them.
    private ref struct Condition {
        private readonly ReadOnlySpan<char> text;
        private readonly IReadOnlySet<string> conditions;
        private int position;

        private Condition(ReadOnlySpan<char> text, IReadOnlySet<string> conditions) {
            this.text = text;
            this.conditions = conditions;
            position = 0;
        }

        /// Whether `expression` holds; one that does not read never holds.
        public static bool Holds(string expression, IReadOnlySet<string> conditions) {
            var condition = new Condition(expression.AsSpan(), conditions);
            bool holds = condition.Either(out bool valid);
            condition.SkipSpace();
            return valid && condition.position == condition.text.Length && holds;
        }

        private bool Either(out bool valid) {
            bool holds = Both(out valid);
            while (valid && Takes("||")) holds |= Both(out valid);
            return holds;
        }

        private bool Both(out bool valid) {
            bool holds = Term(out valid);
            while (valid && Takes("&&")) holds &= Term(out valid);
            return holds;
        }

        private bool Term(out bool valid) {
            if (Takes("!")) return !Term(out valid);
            if (Takes("(")) {
                bool holds = Either(out valid);
                valid = valid && Takes(")");
                return holds;
            }
            SkipSpace();
            int start = position;
            while (position < text.Length && (char.IsAsciiLetterOrDigit(text[position]) || text[position] == '_')) position++;
            valid = position > start;
            return valid && conditions.Contains(text[start..position].ToString());
        }

        private bool Takes(string token) {
            SkipSpace();
            if (!text[position..].StartsWith(token, StringComparison.Ordinal)) return false;
            position += token.Length;
            return true;
        }

        private void SkipSpace() {
            while (position < text.Length && char.IsWhiteSpace(text[position])) position++;
        }
    }

    #endregion
}
