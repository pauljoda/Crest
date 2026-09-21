namespace CrestCore.Contracts;

/// Stable role names in adapter descriptors.
public static class AdapterRoles {
    #region Variables

    public const string Ui = "ui";
    public const string Engine = "engine";
    public const string Platform = "platform";
    public const string Services = "services";

    #endregion

    #region Actions - Validation

    public static bool Includes(string? role)
        => role is Ui or Engine or Platform or Services;

    #endregion
}
