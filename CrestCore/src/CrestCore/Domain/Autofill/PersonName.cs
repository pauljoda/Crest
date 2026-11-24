namespace CrestCore.Domain;

/// A person's name in the parts forms ask for: the given name, any
/// additional names between, and the family name.
internal sealed record PersonName(string Given, string Additional, string Family) {
    #region Variables

    /// The given and additional names together, as a form with one field
    /// before the family name takes them.
    public string Forenames => string.Join(' ', new[] { Given, Additional }.Where(part => part.Length > 0));

    #endregion

    #region Actions - Reading

    /// `full` in its parts: one word is the given name; of more, the first is
    /// the given name, the last the family name and any between additional
    /// names.
    public static PersonName Split(string? full) {
        var words = (full ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return words.Length switch {
            0 => new("", "", ""),
            1 => new(words[0], "", ""),
            _ => new(words[0], string.Join(' ', words[1..^1]), words[^1])
        };
    }

    #endregion
}
