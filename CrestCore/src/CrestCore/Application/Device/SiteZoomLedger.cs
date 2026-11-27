using CrestCore.Contracts;

namespace CrestCore.Application;

#region Types

/// The zoom a browsing profile keeps for one HTTP(S) host.
internal sealed record SiteZoomChoice(Guid ProfileId, string Host, double Factor);

#endregion

/// The zoom each browsing profile keeps for its hosts, least recently chosen
/// first. Past `Maximum`, the least recently chosen goes. A host keeps a zoom
/// only while it differs from the device's default, so a host zoomed back to
/// the default follows the default again. Not thread-safe: the device lock
/// guards it.
internal sealed class SiteZoomLedger {
    #region Static Variables

    /// The most hosts a ledger keeps a zoom for, across its profiles.
    public const int Maximum = 1_024;

    /// How far apart two zooms may be and still be the same level.
    private const double Tolerance = 0.001;

    #endregion

    #region Variables

    private readonly List<SiteZoomChoice> choices = [];

    /// Every choice, least recent first.
    public IReadOnlyList<SiteZoomChoice> Choices => choices;

    #endregion

    #region Actions - Choices

    /// Replaces whatever the ledger held with `kept`, least recent first.
    public void Restore(IEnumerable<SiteZoomChoice> kept) {
        choices.Clear();
        foreach (var choice in kept) Remember(choice);
    }

    /// The zoom `profileId` keeps for `host`, or null when it keeps none.
    public double? Factor(Guid profileId, string host) =>
        choices.LastOrDefault(choice => choice.ProfileId == profileId && choice.Host == host)?.Factor;

    /// Keeps `factor` as `host`'s zoom in `profileId`, as its most recent
    /// choice; null, or a zoom at `defaultZoom`, keeps none. Says whether the
    /// zoom the host follows changed.
    public bool Keep(Guid profileId, string host, double? factor, double defaultZoom) {
        if (factor is not { } zoom || Math.Abs(zoom - defaultZoom) <= Tolerance)
            return choices.RemoveAll(choice => choice.ProfileId == profileId && choice.Host == host) > 0;
        var previous = Factor(profileId, host);
        Remember(new(profileId, host, zoom));
        return previous != zoom;
    }

    /// Forgets the zoom of every profile `forgets` names, and says whether
    /// the ledger held any.
    public bool Forget(Func<Guid, bool> forgets) => choices.RemoveAll(choice => forgets(choice.ProfileId)) > 0;

    /// Holds `choice` as the most recent for its profile and host.
    private void Remember(SiteZoomChoice choice) {
        choices.RemoveAll(held => held.ProfileId == choice.ProfileId && held.Host == choice.Host);
        choices.Add(choice);
        if (choices.Count > Maximum) choices.RemoveRange(0, choices.Count - Maximum);
    }

    #endregion

    #region Actions - Rules

    /// The host whose zoom a page at `url` follows: its HTTP(S) host in ASCII,
    /// lowercased and without a final dot, or null for any other address.
    public static string? Host(string url) => new WebAddress(url).Origin is { IsValid: true } origin
        && origin.Host.TrimEnd('.') is { Length: > 0 } host ? host : null;

    /// Whether a host may keep `factor` as its zoom: a number within the zoom
    /// a page may start at.
    public static bool Allows(double factor) =>
        double.IsFinite(factor) && factor is >= PagePreferences.MinimumZoom and <= PagePreferences.MaximumZoom;

    #endregion
}
