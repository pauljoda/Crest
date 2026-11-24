using CrestCore.Contracts;

namespace CrestCore.Application;

/// The zoom each browsing profile keeps for its sites, by HTTP(S) host. The
/// device store keeps the zoom of the profiles the persistent session's
/// Spaces browse with, and only on a device with a file; a borrowed workspace
/// browses with its owner's profile, so it keeps its owner's zoom. Every other
/// profile's zoom (private, or one no stored session holds) lives in memory
/// while an attached session browses with it. The Spaces of a group share one
/// profile, so they share its zoom, and a Space's own profile keeps its zoom
/// while it waits unused in a group, until a finished deletion erases it.
internal sealed partial class Device {
    #region Variables

    /// The persistent session's profiles' zoom, which the device store keeps.
    private readonly SiteZoomLedger keptSiteZoom = new();
    /// Every other profile's zoom, which lives in memory.
    private readonly SiteZoomLedger passingSiteZoom = new();

    #endregion

    #region Actions - Site zoom

    /// The zoom `url`'s host keeps in the profile of `page`, which lives in
    /// `space`. Called without the device lock, since it reads the sessions.
    internal SiteZoomPreference SiteZoom(Page page, SpaceState space, string url) {
        var keeps = ChoiceScope(space.Id).Keeps;
        var host = SiteZoomLedger.Host(url);
        lock (gate) return new(host, host is null ? null : (keeps ? keptSiteZoom : passingSiteZoom).Factor(page.ProfileId, host));
    }

    /// Keeps `factor` as the zoom of `url`'s host in the profile of `page`,
    /// which lives in `space`, or no zoom of its own when null or the
    /// device's default, and publishes what the host follows when that
    /// changed. Throws `Rejected` for an address without an HTTP(S) host or a
    /// zoom a page may not start at. Called without the device lock, since it
    /// reads the sessions.
    internal void KeepSiteZoom(Page page, SpaceState space, string url, double? factor, ChangeFeed changes) {
        var host = SiteZoomLedger.Host(url) ?? throw new Rejected(new InvalidSiteZoomAddress(url));
        if (factor is { } zoom && !SiteZoomLedger.Allows(zoom)) throw new Rejected(new InvalidSiteZoom(zoom));
        var keeps = ChoiceScope(space.Id).Keeps;
        lock (gate) {
            var ledger = keeps ? keptSiteZoom : passingSiteZoom;
            if (!ledger.Keep(page.ProfileId, host, factor, pages.DefaultZoom)) return;
            if (keeps) storage?.EnqueueDevice(Records());
            changes.Publish(new SiteZoomChanged(page.ProfileId, host, ledger.Factor(page.ProfileId, host)));
        }
    }

    /// A finished deletion erased the data of `profiles`, so they keep no
    /// zoom. No page browses with them any more.
    internal void ForgetSiteZoom(IReadOnlyList<Guid> profiles) {
        lock (gate) {
            if (keptSiteZoom.Forget(profiles.Contains)) storage?.EnqueueDevice(Records());
            passingSiteZoom.Forget(profiles.Contains);
        }
    }

    /// A memory-only profile no attached session browses with any more, such
    /// as a closed private window's, keeps no zoom. Called without the device
    /// lock, since it reads the sessions.
    private void ForgetPassingSiteZoom() {
        NativeSessionAuthority[] attached;
        lock (gate) attached = [.. workspaces.Values];
        var browsing = attached.SelectMany(authority => authority.Current.Spaces)
            .SelectMany(space => new[] { space.OwnProfileId, space.ProfileId }).ToHashSet();
        lock (gate) passingSiteZoom.Forget(profile => !browsing.Contains(profile));
    }

    /// Whether `previous` and `next` hold Spaces that browse with the same
    /// profiles.
    private static bool SameProfiles(SessionState previous, SessionState next) =>
        previous.Spaces.Select(space => (space.OwnProfileId, space.ProfileId))
            .SequenceEqual(next.Spaces.Select(space => (space.OwnProfileId, space.ProfileId)));

    #endregion
}
