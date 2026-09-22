namespace CrestCore.Domain;

/// The composition of Crest's generated passwords. Four explicit groups meet
/// common website requirements; characters that are easily confused in
/// proportional fonts are absent.
public static class StrongPasswordPolicy {
    #region Variables

    public const int DefaultLength = 20;
    public const int MinimumLength = 16;
    public const int MaximumLength = 64;

    private static readonly string[] Groups = [
        "abcdefghijkmnopqrstuvwxyz",
        "ABCDEFGHJKLMNPQRSTUVWXYZ",
        "23456789",
        "-_.!@#$%^&*+="
    ];

    #endregion

    #region Actions - Generation

    /// The recipe for a password of `length` characters, or the default length.
    public static StrongPasswordRecipe Recipe(int? length) {
        int resolved = length ?? DefaultLength;
        if (resolved is < MinimumLength or > MaximumLength) throw new BrowserRuleException(BrowserRuleCodes.InvalidPasswordLength);
        return new(resolved, Groups);
    }

    #endregion
}
