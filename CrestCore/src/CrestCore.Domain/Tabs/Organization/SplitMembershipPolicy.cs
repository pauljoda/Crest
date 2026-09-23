using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Repair never reorders tabs or rewrites position clocks. A singleton keeps
/// its membership because the rest of a sync batch may not have arrived yet.
public static class SplitMembershipPolicy {
    #region Actions - Organization

    public static IReadOnlyList<Guid?> Repair(IReadOnlyList<SplitMember> tabs) {
        var result = new Guid?[tabs.Count];
        HashSet<Guid> retired = [];
        Guid? run = null; TabPlacement placement = default; Guid? folder = null; int length = 0;
        for (int index = 0; index < tabs.Count; index++) {
            var tab = tabs[index];
            if (tab.Group is not { } group || tab.Placement == TabPlacement.Pinned) {
                if (run is { } old) retired.Add(old);
                run = null; length = 0; continue;
            }
            if (run != group) {
                if (run is { } old) retired.Add(old);
                run = null; length = 0;
                if (retired.Contains(group)) continue;
                run = group; placement = tab.Placement; folder = tab.Folder; length = 1;
            } else {
                if (tab.Placement != placement || tab.Folder != folder) { retired.Add(group); run = null; length = 0; continue; }
                if (length >= BrowserTabCollection.MaximumSplitMembers) continue;
                length++;
            }
            result[index] = group;
        }
        return result;
    }

    #endregion
}
