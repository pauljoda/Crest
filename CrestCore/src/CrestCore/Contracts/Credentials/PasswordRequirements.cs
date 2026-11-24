using System.Globalization;

namespace CrestCore.Contracts;

/// What a site asks of a new password: the field's `minlength` and
/// `maxlength`, and its `passwordrules` attribute as the page wrote it, in the
/// grammar of required and allowed character classes, `max-consecutive`,
/// `minlength` and `maxlength` rules. A rule Crest cannot read is ignored, so
/// a page never stops Crest from making a password, only shapes it.
public sealed record PasswordRequirements(int? MinLength, int? MaxLength, string? Rules) {
    #region Types

    /// The rules attribute, read: each required set, the allowed characters
    /// (null when the page names no classes), and the limits it adds.
    private sealed record ReadRules(List<HashSet<char>> Required, HashSet<char>? Allowed, int? MinLength, int? MaxLength,
        int? MaxConsecutive);

    #endregion

    #region Static Variables

    /// A site with no requirements.
    public static PasswordRequirements None { get; } = new(null, null, null);

    /// The longest rules attribute Crest reads.
    private const int MaximumRulesLength = 1_024;

    private const string Uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    private const string Lowercase = "abcdefghijklmnopqrstuvwxyz";
    private const string Digits = "0123456789";
    private const string Specials = "-~!@#$%^&*_+=`|(){}[:;\"'<>,.?] ";

    /// The refusal of requirements no password Crest makes can meet.
    private static InvalidPasswordLength Unmakeable =>
        new(StrongPasswordRecipe.ShortestLength, StrongPasswordRecipe.MaximumLength);

    #endregion

    #region Actions - Generation

    /// How to compose a password that meets these requirements: Crest's
    /// grouped style where the site allows it, and otherwise random
    /// characters from what the site allows, of the default length or the
    /// nearest the site permits.
    internal StrongPasswordRecipe Recipe() {
        var rules = Read(Rules);
        int shortest = Math.Max(MinLength ?? 0, rules.MinLength ?? 0);
        int longest = Math.Min(MaxLength ?? StrongPasswordRecipe.MaximumLength, rules.MaxLength ?? StrongPasswordRecipe.MaximumLength);
        // A length Crest can't make, or one the site contradicts, is refused
        // rather than bent below the site's own minimum.
        if (longest < StrongPasswordRecipe.ShortestLength || shortest > longest) throw new Rejected(Unmakeable);
        int maxConsecutive = rules.MaxConsecutive ?? 0;
        if (AllowsGrouped(rules) && StrongPasswordRecipe.GroupedLength >= shortest && StrongPasswordRecipe.GroupedLength <= longest)
            return StrongPasswordRecipe.Grouped(maxConsecutive);
        int length = Math.Clamp(StrongPasswordRecipe.DefaultLength, Math.Max(shortest, StrongPasswordRecipe.ShortestLength), longest);
        if (rules.Allowed is null) return StrongPasswordRecipe.Random(length, StrongPasswordRecipe.CharacterGroups,
            StrongPasswordRecipe.CharacterGroups, maxConsecutive);
        var groups = Drawable(rules.Allowed);
        var required = Essential(rules.Required).Select(set => string.Concat(Drawable(set))).ToList();
        if (required.Count > length) throw new Rejected(Unmakeable);
        return StrongPasswordRecipe.Random(length, groups, required, maxConsecutive);
    }

    /// The required sets that each ask for something the others don't: a set
    /// holding all of another is met whenever that other one is, and of sets
    /// that are the same only the first is kept.
    private static List<HashSet<char>> Essential(List<HashSet<char>> sets) =>
        [.. sets.Where((set, index) => !sets.Where((other, otherIndex) => otherIndex != index
            && (other.IsProperSubsetOf(set) || otherIndex < index && other.SetEquals(set))).Any())];

    /// Whether the rules let a grouped password through: they allow its
    /// letters, digits and hyphens, and every required set takes every
    /// character of one of its kinds, or the hyphen.
    private static bool AllowsGrouped(ReadRules rules) {
        var kinds = StrongPasswordRecipe.GroupedCharacters;
        if (rules.Allowed is { } allowed && !kinds.All(kind => kind.All(allowed.Contains))) return false;
        return rules.Required.All(set => kinds.Any(kind => kind.All(set.Contains)));
    }

    /// The characters of `set` Crest draws from, split by kind, any the page
    /// named outside the named classes among them, and without the ones easily
    /// confused in a proportional font, spaces and quotes, as long as some remain.
    private static IReadOnlyList<string> Drawable(HashSet<char> set) {
        string named = Lowercase + Uppercase + Digits + Specials;
        string[] kinds = [Lowercase, Uppercase, Digits, Specials, new([.. set.Where(character => !named.Contains(character)).Order()])];
        return [.. kinds.Select(kind => Unambiguous(new string([.. kind.Where(set.Contains)]))).Where(group => group.Length > 0)];
    }

    /// `characters` without the ambiguous ones, while at least two remain, so a
    /// limit on repeats can still be met.
    private static string Unambiguous(string characters) {
        string clear = new([.. characters.Where(character => !StrongPasswordRecipe.Ambiguous.Contains(character))]);
        return clear.Length >= 2 || clear.Length == characters.Length ? clear : characters;
    }

    #endregion

    #region Actions - Reading

    /// The rules `text` spells, skipping any it cannot read.
    private static ReadRules Read(string? text) {
        var required = new List<HashSet<char>>();
        HashSet<char>? allowed = null;
        int? shortest = null, longest = null, maxConsecutive = null;
        if (string.IsNullOrWhiteSpace(text) || text.Length > MaximumRulesLength) return new(required, allowed, null, null, null);
        foreach (string rule in RuleTexts(text)) {
            int colon = rule.IndexOf(':', StringComparison.Ordinal);
            if (colon < 0) continue;
            string name = rule[..colon].Trim().ToLowerInvariant();
            string value = rule[(colon + 1)..].Trim();
            switch (name) {
                case "required" when Classes(value) is { Count: > 0 } set:
                    required.Add(set);
                    allowed = [.. allowed ?? [], .. set];
                    break;
                case "allowed" when Classes(value) is { Count: > 0 } set:
                    allowed = [.. allowed ?? [], .. set];
                    break;
                // A rule given twice holds to the stricter value.
                case "minlength": shortest = Stricter(shortest, Number(value), Math.Max); break;
                case "maxlength": longest = Stricter(longest, Number(value), Math.Min); break;
                case "max-consecutive": maxConsecutive = Stricter(maxConsecutive, Number(value), Math.Min); break;
            }
        }
        return new(required, allowed, shortest, longest, maxConsecutive);
    }

    /// The rules of `text`, split at each semicolon outside a bracketed set, so
    /// a set such as `[!;@]` stays whole. A closing bracket right after the
    /// opening one is the set's own only when another closes it, as in `[]]`;
    /// otherwise `[]` is an empty set, which is ignored.
    private static IEnumerable<string> RuleTexts(string text) {
        int start = 0;
        int index = 0;
        while (index < text.Length) {
            char character = text[index];
            if (character == '[') {
                index = SetEnd(text, index) + 1;
                continue;
            }
            if (character == ';') {
                yield return text[start..index];
                start = index + 1;
            }
            index++;
        }
        yield return text[start..];
    }

    /// Where the bracketed set opening at `open` closes, or the text's end.
    private static int SetEnd(string text, int open) {
        bool leadingBracket = open + 2 < text.Length && text[open + 1] == ']' && text[open + 2] == ']';
        int close = text.IndexOf(']', leadingBracket ? open + 2 : open + 1);
        return close < 0 ? text.Length - 1 : close;
    }

    /// The characters a comma-separated list of classes names: `upper`,
    /// `lower`, `digit`, `special`, `ascii-printable`, `unicode` (read as
    /// printable ASCII) and bracketed sets such as `[-_.]`.
    private static HashSet<char> Classes(string value) {
        var characters = new HashSet<char>();
        int index = 0;
        while (index < value.Length) {
            char character = value[index];
            if (character is ',' or ' ') { index++; continue; }
            if (character == '[') {
                int close = SetEnd(value, index);
                if (close >= value.Length || value[close] != ']') break;
                characters.UnionWith(value[(index + 1)..close].Where(char.IsAscii).Where(member => !char.IsControl(member)));
                index = close + 1;
                continue;
            }
            int end = value.IndexOfAny([',', ' ', '['], index);
            if (end < 0) end = value.Length;
            characters.UnionWith(ClassNamed(value[index..end].ToLowerInvariant()));
            index = end;
        }
        return characters;
    }

    private static string ClassNamed(string name) => name switch {
        "upper" => Uppercase,
        "lower" => Lowercase,
        "digit" => Digits,
        "special" => Specials,
        "ascii-printable" or "unicode" => Uppercase + Lowercase + Digits + Specials,
        _ => ""
    };

    private static int? Stricter(int? kept, int? read, Func<int, int, int> choose) =>
        read is not int number ? kept : kept is int earlier ? choose(earlier, number) : number;

    private static int? Number(string value) =>
        int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out int number) && number is >= 0 and <= 1_000 ? number : null;

    #endregion
}
