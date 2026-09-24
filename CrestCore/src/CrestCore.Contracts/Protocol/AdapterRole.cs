namespace CrestCore.Contracts;

/// The slot an adapter fills in the core's session contract. Descriptors spell
/// a role as its `Name`.
public sealed class AdapterRole {
    #region Variables

    public static readonly AdapterRole Ui = new(name: "ui");
    public static readonly AdapterRole Engine = new(name: "engine");
    public static readonly AdapterRole Platform = new(name: "platform");
    public static readonly AdapterRole Services = new(name: "services");

    public static IReadOnlyList<AdapterRole> All { get; } = [Ui, Engine, Platform, Services];

    public string Name { get; }

    #endregion

    #region Constructors

    private AdapterRole(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static AdapterRole? Named(string? name) => All.FirstOrDefault(role => role.Name == name);

    #endregion
}
