namespace CrestCore.Contracts;

/// How to compose a generated password of `Length` characters, or of the
/// default length when it is null. The password itself never exists in the core.
public sealed record StrongPassword(int? Length) : Query<StrongPasswordRecipe>;
