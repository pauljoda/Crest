using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

#region Types

/// A topic Tidy found among a Space's loose open tabs: its name, in the app's
/// language, and its tabs in sidebar order.
public sealed record TidyTopic(string Title, IReadOnlyList<Guid> TabIds);

#endregion

/// Files a Space's loose open tabs into a group for each topic Tidy found, in
/// one edit. A topic joins the end of the group Tidy made for a topic of the
/// same name, which opens if it was collapsed; otherwise Tidy makes a group for
/// it where its first tab is. A group a person made is never filled. Only an
/// open tab outside every folder, group and split may be filed, each in one
/// topic: refused with `TabCannotBeTidied` for any other tab and
/// `TidyTopicNeedsTwoTabs` for a topic of fewer than two, and then nothing
/// changes.
public sealed record TidyTabs(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<TidyTopic> Topics) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Creation, edited => {
            RequireTidyableTabs(edited);
            var groupsByName = new Dictionary<string, Guid>();
            foreach (var topic in Topics) {
                var title = NativeSessionAuthority.FolderTitle(topic.Title);
                var name = FolderState.MatchKey(title);
                if (!groupsByName.TryGetValue(name, out var groupId)) {
                    if (edited.Folders.FirstOrDefault(folder => folder.TakesTidyTopic(name)) is { } made) {
                        groupId = made.Id;
                        edited.CollapseFolder(groupId, collapsed: false, turn.Now);
                    } else {
                        groupId = turn.Ids.Next();
                        edited.AddFolder(groupId, title, TabPlacement.Current, isGroup: true, madeByTidy: true);
                        edited.SetFolderColor(groupId, FolderState.DefaultColor);
                    }
                    if (name.Length > 0) groupsByName[name] = groupId;
                }
                edited.FileTabs(topic.TabIds, TabPlacement.Current, groupId, turn.Now);
            }
        });

    /// Checks every topic before anything changes.
    private void RequireTidyableTabs(BrowserTabCollection edited) {
        var filedTabIds = new HashSet<Guid>();
        foreach (var topic in Topics) {
            if (topic.TabIds.Count < 2) throw new Rejected(new TidyTopicNeedsTwoTabs(topic.Title));
            foreach (var tabId in topic.TabIds) {
                if (!filedTabIds.Add(tabId)) throw new Rejected(new TabCannotBeTidied(tabId));
                var tab = edited.Tab(tabId);
                if (tab.Placement != TabPlacement.Current || tab.FolderId is not null || tab.SplitGroupId is not null)
                    throw new Rejected(new TabCannotBeTidied(tabId));
            }
        }
    }

    #endregion
}
