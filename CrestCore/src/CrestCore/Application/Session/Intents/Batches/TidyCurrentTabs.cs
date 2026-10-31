using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

#region Types

/// A header Tidy proposes, named in the app's language, and the tabs it holds.
public sealed record TidyFolderProposal(string FolderTitle, IReadOnlyList<Guid> TabIds);

#endregion

/// Files a Space's open tabs under the headers Tidy proposes, in one edit: each
/// header is made in the open section with its tabs, unless a Tidy header at
/// the open section's top level already has its name, which then takes the
/// tabs after its own and opens if it was collapsed. Only an open tab outside
/// every folder and split may be filed, each under at most one header. Refused
/// with `TabCannotBeTidied` for any other tab and `TidyFolderNeedsTwoTabs` for
/// a header of fewer than two, and then nothing changes.
public sealed record TidyCurrentTabs(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<TidyFolderProposal> Folders)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Creation, edited => {
            RequireTidyableTabs(edited);
            var headersByName = edited.Folders
                .Where(folder => folder.IsTidyHeader && folder.Location == TabPlacement.Current && folder.ParentId is null)
                .GroupBy(folder => FolderState.MatchKey(folder.Title))
                .Where(named => named.Key.Length > 0)
                .ToDictionary(named => named.Key, named => named.First().Id);
            foreach (var folder in Folders) {
                var title = NativeSessionAuthority.FolderTitle(folder.FolderTitle);
                var name = FolderState.MatchKey(title);
                if (headersByName.TryGetValue(name, out var folderId)) {
                    edited.CollapseFolder(folderId, collapsed: false, turn.Now);
                } else {
                    folderId = turn.Ids.Next();
                    edited.AddFolder(folderId, title, TabPlacement.Current, isTidyHeader: true);
                    if (name.Length > 0) headersByName[name] = folderId;
                }
                edited.FileTabs(folder.TabIds, TabPlacement.Current, folderId, turn.Now);
            }
        });

    /// Checks every proposal before anything changes.
    private void RequireTidyableTabs(BrowserTabCollection edited) {
        var filedTabIds = new HashSet<Guid>();
        foreach (var folder in Folders) {
            if (folder.TabIds.Count < 2) throw new Rejected(new TidyFolderNeedsTwoTabs(folder.FolderTitle));
            foreach (var tabId in folder.TabIds) {
                if (!filedTabIds.Add(tabId)) throw new Rejected(new TabCannotBeTidied(tabId));
                var tab = edited.Tab(tabId);
                if (tab.Placement != TabPlacement.Current || tab.FolderId is not null || tab.SplitGroupId is not null)
                    throw new Rejected(new TabCannotBeTidied(tabId));
            }
        }
    }

    #endregion
}
