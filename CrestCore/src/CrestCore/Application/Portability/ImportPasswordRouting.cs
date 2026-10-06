using System.Net;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// Which of the Spaces a browser brought each of its saved passwords belongs
/// with. A browser whose Spaces are its profiles gives a password to its own
/// profile's Space and to no other; one that names its own Spaces gives it to
/// every Space holding its site, or a site one of them is a subdomain of. A
/// browser that keeps no passwords routes none.
internal static class ImportPasswordRouting {
    #region Types

    /// The hosts a Space's tabs show or were saved at, and every domain those
    /// hosts are, or are a subdomain of, compared ignoring case.
    private sealed record Sites(IReadOnlySet<string> Hosts, IReadOnlySet<string> Domains);

    #endregion

    #region Actions - Routing

    /// How many of `passwords` belong with each of `spaces`, by Space.
    public static IReadOnlyDictionary<Guid, int> Counts(ImportSource source, IReadOnlyList<ImportPasswordSource> passwords,
        IReadOnlyList<SpaceState> spaces) {
        ArgumentNullException.ThrowIfNull(passwords);
        var sites = SitesOf(spaces);
        var counts = new Dictionary<Guid, int>();
        foreach (var password in passwords)
            foreach (var spaceId in SourceSpaces(source, password, spaces, sites))
                counts[spaceId] = counts.GetValueOrDefault(spaceId) + 1;
        return counts;
    }

    /// Where each of `passwords` goes once `review` is imported into
    /// `session`: the destination of each reviewed Space the password belongs
    /// with that brings its passwords, leaving out a destination `session` no
    /// longer holds or `isLocked` holds shut. A password whose Space does not
    /// bring its passwords goes nowhere, never to another profile's Space.
    public static ImportPasswordRoutes Destinations(SetupImportReview review, IReadOnlyList<ImportPasswordSource> passwords,
        SessionState session, Func<SpaceState, bool> isLocked) {
        ArgumentNullException.ThrowIfNull(review);
        ArgumentNullException.ThrowIfNull(passwords);
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(isLocked);
        var reviewed = review.Spaces.Select(space => space.Source).ToArray();
        var destinations = review.Spaces.Where(space => space.BringsPasswords)
            .ToDictionary(space => space.Source.Id, space => space.DestinationId ?? space.Source.Id);
        var open = session.Spaces.Where(space => !isLocked(space)).Select(space => space.Id).ToHashSet();
        var sites = SitesOf(reviewed);
        return new([.. passwords.Select(password => new ImportPasswordRoute([.. SourceSpaces(review.Source, password, reviewed, sites)
            .Where(destinations.ContainsKey).Select(spaceId => destinations[spaceId]).Distinct().Where(open.Contains)]))]);
    }

    /// The Spaces among `spaces` that `password` belongs with.
    private static IEnumerable<Guid> SourceSpaces(ImportSource source, ImportPasswordSource password, IReadOnlyList<SpaceState> spaces,
        IReadOnlyDictionary<Guid, Sites> sites) {
        if (!source.SuppliesPasswords) return [];
        if (source.NamesItsSpaces) return spaces.Where(space => Holds(sites[space.Id], password.Host)).Select(space => space.Id);
        var profile = spaces.FirstOrDefault(space => string.Equals(space.Settings.Name, password.ProfileName, StringComparison.Ordinal));
        return profile is null ? [] : [profile.Id];
    }

    #endregion

    #region Actions - Sites

    /// Each Space's sites.
    private static IReadOnlyDictionary<Guid, Sites> SitesOf(IReadOnlyList<SpaceState> spaces) {
        ArgumentNullException.ThrowIfNull(spaces);
        var sites = new Dictionary<Guid, Sites>();
        foreach (var space in spaces) {
            var hosts = space.Tabs.Select(tab => ImportAddress.Read(tab.SavedUrl ?? tab.Url)?.Host).OfType<string>()
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            sites[space.Id] = new(hosts, hosts.SelectMany(Domains).ToHashSet(StringComparer.OrdinalIgnoreCase));
        }
        return sites;
    }

    /// Whether `sites` holds `host`, a subdomain of it, or a domain it is a
    /// subdomain of, each at a dot.
    private static bool Holds(Sites sites, string host) => sites.Domains.Contains(host) || Domains(host).Any(sites.Hosts.Contains);

    /// `host` and each domain it is a subdomain of, at a dot: itself only for
    /// an address.
    private static IEnumerable<string> Domains(string host) {
        yield return host;
        if (IPAddress.TryParse(host, out _)) yield break;
        for (int dot = host.IndexOf('.', StringComparison.Ordinal); dot >= 0 && dot + 1 < host.Length;
            dot = host.IndexOf('.', dot + 1)) yield return host[(dot + 1)..];
    }

    #endregion
}
