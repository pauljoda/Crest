namespace CrestCore.Contracts;

/// Forgets one saved choice, so the site asks again. A locked Space's choice
/// is forgotten too; a record that is gone changes nothing.
public sealed record ResetSitePermission(Guid RecordId) : SitePermissionIntent;
