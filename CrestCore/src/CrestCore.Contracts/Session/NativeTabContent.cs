namespace CrestCore.Contracts;

/// <summary>A native view a tab shows instead of a web page. <see cref="Kind"/> stays
/// open so a view another build added survives here; <see cref="ResourceId"/> names a
/// separately stored document the view shows.</summary>
public sealed record NativeTabContent(string Kind, Guid? ResourceId = null);
