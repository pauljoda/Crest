using CrestCore.Application;

namespace CrestCore.Contracts;

/// How to compose a generated password that meets `Requirements`, the limits
/// of the field it is for. The password itself never exists in the core.
public sealed record StrongPassword(PasswordRequirements Requirements) : Query<StrongPasswordRecipe> {
    #region Actions - Answering

    internal override StrongPasswordRecipe Answer(CrestApp app) {
        ArgumentNullException.ThrowIfNull(Requirements);
        return Requirements.Recipe();
    }

    #endregion
}
