namespace CrestCore.Contracts;

/// The key a Quick Window remembers its Space under for `Url`, when Quick
/// Windows remember Spaces by site.
public sealed record QuickWindowSite(string Url, bool RemembersSpaceBySite) : Query<QuickWindowSiteKey>;
