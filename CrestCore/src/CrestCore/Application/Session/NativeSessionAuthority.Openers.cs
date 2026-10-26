using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// The last tab each opener opened, so the tabs one opener opens cluster
    /// together. Runtime only: it is neither saved nor synced, and a tab that
    /// is gone, moved to another section or in another Space is simply not
    /// found, which places the next tab after the current one.
    private readonly Dictionary<Guid, Guid> lastOpened = [];

    #endregion

    #region Actions - Openers

    /// The tab `opener` opened last that is still in `space`'s section
    /// `placement`, or null for no opener or none such tab. The caller holds
    /// the gate.
    internal Guid? LastOpenedBy(Guid? opener, SpaceState space, TabPlacement placement) =>
        opener is { } id && lastOpened.TryGetValue(id, out var tabId)
            && space.Tabs.Any(tab => tab.Id == tabId && tab.Placement == placement)
                ? tabId
                : null;

    /// Remembers the tab an opener opened, and forgets each opener whose tab
    /// `next` no longer holds. The caller holds the gate.
    private void RememberOpened(OpenedTab opened, SessionState next) {
        lastOpened[opened.OpenerId] = opened.TabId;
        var kept = next.Spaces.SelectMany(space => space.Tabs).Select(tab => tab.Id).ToHashSet();
        foreach (var opener in lastOpened.Where(entry => !kept.Contains(entry.Value)).Select(entry => entry.Key).ToList())
            lastOpened.Remove(opener);
    }

    #endregion
}
