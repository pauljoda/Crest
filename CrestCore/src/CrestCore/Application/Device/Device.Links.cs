using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// This device's link preferences, which the device store keeps and never
/// syncs, and where a link another app hands a window, or a link a route
/// claims on a page, opens under them.
internal sealed partial class Device {
    #region Variables

    private LinkPreferences links = LinkPreferences.Default;
    internal LinkPreferences Links { get => links; set => links = value; }

    #endregion

    #region Actions - Link intents

    /// Runs one link intent, publishing the preferences when they changed.
    public void Handle(LinkIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Keeps the preferences `revise` makes of the device's own, and publishes
    /// them when they changed.
    internal void ReviseLinks(ChangeFeed changes, Func<LinkPreferences, LinkPreferences> revise) {
        lock (gate) Revise(revise(links), changes);
    }

    /// Forgets a deleted Space in the link preferences: its routes, its
    /// choice as the external-link Space and the sites that remembered it.
    public void ForgetLinks(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) Revise(links.Forgetting(spaceId), changes);
    }

    /// Keeps `revised` and publishes it when it differs from the preferences
    /// the device holds. The caller holds the device lock.
    private void Revise(LinkPreferences revised, ChangeFeed changes) {
        if (revised.Equals(links)) return;
        links = revised;
        storage?.EnqueueDevice(Records());
        changes.Publish(new LinkPreferencesChanged(links));
    }

    #endregion

    #region Actions - Routing

    /// The Space a link to `url` followed from a page of `spaceId` showing
    /// `shown` opens in instead of that Space: the one the first enabled route
    /// that matches names, when it is another Space of `workspace` that can
    /// take a tab now, neither locked, being deleted nor at its tab limit,
    /// since the platform cancels the click before it opens the tab. Null when
    /// the link stays where it was followed: it stays on the site the page
    /// shows, and it stays when the first matching route names the page's own
    /// Space or one that cannot open; a later route never takes its place. A
    /// locked Space is never unlocked on a link's behalf.
    private static SpaceState? RoutedSpace(LinkPreferences preferences, string url, string? shown,
        NativeSessionAuthority workspace, Guid spaceId) {
        if (shown is not null && RememberedSite.SiteOf(shown) is { } site && site == RememberedSite.SiteOf(url)) return null;
        if (preferences.RoutedSpace(url, _ => true) is not { } routed || routed == spaceId) return null;
        var space = workspace.Current.Space(routed);
        return space is not null && space.Tabs.Count < BrowserTabCollection.MaximumTabs && !workspace.IsDeleting(routed)
            && !workspace.IsLocked(space)
            ? space
            : null;
    }

    /// What following a link from a page does: a page for a tab reads the
    /// tab's place and saved address, a Peek brings the tabs it opens to the
    /// front, and the rest follows this device's link preferences. A link a
    /// route sends to another Space opens in a new tab there, which the answer
    /// names, unless the person asked for Peek.
    public LinkNavigationAnswer Answer(LinkNavigation question, Pages pages) {
        ArgumentNullException.ThrowIfNull(question);
        ArgumentNullException.ThrowIfNull(pages);
        LinkPreferences preferences;
        lock (gate) preferences = links;
        var gesture = question.Gesture;
        var (peek, newTab) = preferences.PeekModifier.Intent(gesture.Modifiers, gesture.MiddleClick);
        var page = pages.Hosted(question.PageId);
        var workspace = page is null ? null : Attached(page.WorkspaceId);
        var tab = page is { TabId: { } tabId }
            ? workspace?.Current.Space(page.SpaceId)?.Tabs.FirstOrDefault(candidate => candidate.Id == tabId)
            : null;
        bool focuses = preferences.FocusesNewTabs || page is { TabId: null, Transient.OpensNewTabsInFront: true };
        var routed = tab is not null && workspace is not null && question.Url is { } url
            ? RoutedSpace(preferences, url, page!.Live.Url ?? tab.Url, workspace, page.SpaceId)
            : null;
        var decision = LinkNavigationDecision.For(question.Url, gesture.UserActivated, gesture.TopLevel, peek, newTab,
            gesture.Modifiers.HasFlag(ShortcutModifiers.Shift), focuses, hasContext: tab is not null, tab?.Placement,
            tab?.SavedAddress, preferences.OpensPeekAutomatically, routedElsewhere: routed is not null);
        return new(decision, decision.OpensTab ? routed?.Id : null);
    }

    #endregion
}
