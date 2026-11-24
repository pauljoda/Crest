namespace CrestCore.Contracts;

/// How a strong password is composed, so the platform can draw it with its own
/// secure random source and the password itself never exists in the core.
/// The password is `Segments` runs of `SegmentLength` characters joined by
/// `Separator`. Each character comes from all of `Groups`, then one character
/// of each `Required` group takes a different random place. No character
/// repeats more than `MaxConsecutive` times in a row, where that is above 0.
/// Crest's own style is three groups of six lowercase letters, one of them
/// uppercase and one a digit, joined by hyphens: easy to read and to type,
/// and accepted where hyphens are. Characters easily confused in
/// proportional fonts are left out wherever a site allows others.
public sealed record StrongPasswordRecipe(int Segments, int SegmentLength, string Separator, IReadOnlyList<string> Groups,
    IReadOnlyList<string> Required, int MaxConsecutive) {
    #region Static Variables

    internal const int DefaultLength = 20;
    internal const int ShortestLength = 4;
    internal const int MaximumLength = 128;

    private const int GroupedSegments = 3;
    private const int GroupedSegmentLength = 6;
    private const string GroupedSeparator = "-";

    /// Characters easily confused in a proportional font, or easily mistyped.
    internal const string Ambiguous = "lI1O0| `'\"\\";

    private const string Lowercase = "abcdefghijkmnopqrstuvwxyz";
    private const string Uppercase = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    private const string Digits = "23456789";
    private const string Specials = "-_.!@#$%^&*+=";

    /// The four groups of a random password: one of each, the rest from all.
    internal static IReadOnlyList<string> CharacterGroups { get; } = [Lowercase, Uppercase, Digits, Specials];

    /// Every kind of character a grouped password holds.
    internal static IReadOnlyList<string> GroupedCharacters { get; } = [Lowercase, Uppercase, Digits, GroupedSeparator];

    /// The length of a grouped password, separators included.
    internal static int GroupedLength => GroupedSegments * GroupedSegmentLength + (GroupedSegments - 1) * GroupedSeparator.Length;

    #endregion

    #region Variables

    /// The password's length, separators included.
    internal int Length => Segments * SegmentLength + (Segments - 1) * Separator.Length;

    #endregion

    #region Actions - Generation

    /// Crest's grouped style.
    internal static StrongPasswordRecipe Grouped(int maxConsecutive) =>
        new(GroupedSegments, GroupedSegmentLength, GroupedSeparator, [Lowercase], [Uppercase, Digits], maxConsecutive);

    /// `length` random characters from `groups`, with one from each of `required`.
    internal static StrongPasswordRecipe Random(int length, IReadOnlyList<string> groups, IReadOnlyList<string> required,
        int maxConsecutive) =>
        new(1, length, "", groups, required, maxConsecutive);

    #endregion
}
