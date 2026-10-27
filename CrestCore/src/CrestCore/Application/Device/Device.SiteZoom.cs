using CrestCore.Contracts;

namespace CrestCore.Application;

/// Host zoom is local to a browsing profile. Borrowed workspaces use their
/// source profile; private and other memory-only profiles never reach disk.
internal sealed partial class Device {
    #region Variables

    private readonly Dictionary<(Guid ProfileId, string Host), double> keptSiteZoom = [];
    private readonly Dictionary<(Guid ProfileId, string Host), double> passingSiteZoom = [];

    #endregion

    #region Actions - Site zoom

    internal SiteZoomPreference SiteZoom(Page page, string url) {
        var keeps = SiteZoomScope(page);
        var host = ZoomHost(url);
        lock (gate) return new(host, host is not null && (keeps ? keptSiteZoom : passingSiteZoom)
            .TryGetValue((page.ProfileId, host), out var factor) ? factor : null);
    }

    internal void SetSiteZoom(Page page, string url, double? factor, ChangeFeed changes) {
        var keeps = SiteZoomScope(page);
        var host = ZoomHost(url) ?? throw new Rejected(new InvalidSiteZoomAddress(url));
        if (factor is { } value && !ValidSiteZoom(value)) throw new Rejected(new InvalidSiteZoom(value));
        lock (gate) {
            var choices = keeps ? keptSiteZoom : passingSiteZoom;
            var key = (page.ProfileId, host);
            if (factor is { } zoom) {
                if (choices.TryGetValue(key, out var previous) && previous == zoom) return;
                choices[key] = zoom;
            } else if (!choices.Remove(key)) return;
            if (keeps) storage?.EnqueueDevice(Records());
            changes.Publish(new SiteZoomChanged(page.ProfileId, host));
        }
    }

    private bool SiteZoomScope(Page page) {
        var authority = Workspace(page.WorkspaceId);
        var space = authority.Current.Spaces.FirstOrDefault(space => space.Id == page.SpaceId)
            ?? throw new Rejected(new UnknownSpace(page.SpaceId));
        if (authority.IsDeleting(space.Id)) throw new Rejected(new SpaceBeingDeleted(space.Id));
        if (authority.IsLocked(space)) throw new Rejected(new SpaceLocked(space.Id));
        if (space.ProfileId != page.ProfileId) throw new Rejected(new PageProfileMismatch(page.Id, space.Id));
        return ChoiceScope(space.Id).Keeps;
    }

    internal static string? ZoomHost(string url) {
        var origin = new WebAddress(url).Origin;
        var host = origin?.Host.TrimEnd('.');
        return origin is { IsValid: true } && host is { Length: > 0 } ? host : null;
    }

    internal static bool ValidSiteZoom(double factor) => double.IsFinite(factor) && factor is >= 0.25 and <= 5;

    /// A removed or replaced persistent profile leaves no saved site choices.
    /// Closing a private workspace forgets its choices immediately.
    private void PruneSiteZoom(Guid? changedWorkspace = null) {
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        Guid? persistent;
        lock (gate) {
            attached = [.. workspaces];
            persistent = persistentWorkspace;
        }
        var liveProfiles = attached.SelectMany(entry => entry.Value.Current.Spaces.Select(space => space.ProfileId)).ToHashSet();
        var keptProfiles = changedWorkspace is not null && changedWorkspace == persistent
            ? attached.Where(entry => entry.Key == persistent).SelectMany(entry => entry.Value.Current.Spaces
                .Where(space => !entry.Value.IsDeleting(space.Id)).Select(space => space.ProfileId)).ToHashSet()
            : null;
        lock (gate) {
            foreach (var key in passingSiteZoom.Keys.Where(key => !liveProfiles.Contains(key.ProfileId)).ToArray())
                passingSiteZoom.Remove(key);
            if (keptProfiles is null) return;
            var removed = keptSiteZoom.Keys.Where(key => !keptProfiles.Contains(key.ProfileId)).ToArray();
            foreach (var key in removed) keptSiteZoom.Remove(key);
            if (removed.Length > 0) storage?.EnqueueDevice(Records());
        }
    }

    #endregion
}
