namespace CrestCore.Contracts;

/// How a strong password is composed: its length and the character groups it
/// draws from. The platform draws one character from every group, fills the
/// rest from all groups and shuffles, using its own secure random source, so
/// the password itself never exists in the core.
public sealed record StrongPasswordRecipe(int Length, IReadOnlyList<string> Groups);
