using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class BrowserKernel
{
    private void ReleaseInactivePages(Envelope m)
    {
        Protocol.Members(m.Payload, "level", "platform");
        var level = Protocol.Text(m.Payload, "level");
        var host = Protocol.Text(m.Payload, "platform");
        if (level is not ("warning" or "critical") || host is not ("desktop" or "mobile"))
            throw new BrowserRuleException("invalid_memory_pressure");
        if (quiescing || !engine.Supports("page-residency")) return;
        // The native adapter makes the final media/capture safety decision. The
        // core owns ordering, the keep-loaded preference, and window/split scope.
        if (workspace.Windows.FirstOrDefault() is not { } window) return;
        var candidates = workspace.Spaces.Where(s => !s.IsDeleting).SelectMany(space =>
        {
            var protectedTabs = workspace.ProtectedTabs(space.Id);
            return space.Tabs.Where(tab => tab.Kind == TabKind.Web && tab.Phase == TabPhase.Ready
                && !tab.KeepsPageLoaded && !tab.IsLoading && !protectedTabs.Contains(tab.Id)
                && !pending.Values.Any(p => p.Tab == tab.Id))
                .Select(tab => (Space: space, Tab: tab));
        }).OrderBy(pair => pair.Tab.LastActivatedAt).ThenBy(pair => pair.Tab.Id.Value).ToArray();
        int count = (host, level) switch
        {
            ("mobile", "warning") => 0,
            ("mobile", "critical") or ("desktop", "warning") => 1,
            _ => (candidates.Length + 1) / 2
        };
        foreach (var (space, tab) in candidates.Take(count))
        {
            tab.RequestUnload();
            Effect(m, "engine.unload_page", space, tab, window.Id);
        }
        if (count > 0 && candidates.Length > 0) Snapshot(m);
    }
}
