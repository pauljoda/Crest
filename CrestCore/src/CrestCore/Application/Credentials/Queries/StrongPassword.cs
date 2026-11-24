using CrestCore.Application;

namespace CrestCore.Contracts;

/// How to compose a generated password in `Style` that meets `Requirements`,
/// the limits of the field it is for. The password itself never exists in the
/// core.
public sealed record StrongPassword(PasswordRequirements Requirements, PasswordStyle Style) : Query<StrongPasswordRecipe> {
    #region Actions - Answering

    internal override StrongPasswordRecipe Answer(CrestApp app) {
        ArgumentNullException.ThrowIfNull(Requirements);
        ArgumentNullException.ThrowIfNull(Style);
        return Requirements.Recipe(Style);
    }

    #endregion
}
