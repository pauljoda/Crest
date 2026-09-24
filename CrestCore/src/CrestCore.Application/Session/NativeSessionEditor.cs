using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Applies one domain edit to a Space's organization. The authority publishes the
/// result atomically, and the native store then reconciles its live pages.
/// History, existing archive records and image payloads are never part of an edit.
internal static class NativeSessionEditor {
    #region Variables

    private const string NewFolderTitle = "New Folder";
    private const string UntitledFolderTitle = "Untitled Folder";

    private sealed class SuppliedIds(IReadOnlyList<Guid> values) : IIdSource {
        #region Variables

        private readonly Queue<Guid> values = new(values);

        #endregion

        #region Actions - Identity supply

        public Guid Next() => values.Dequeue();

        #endregion
    }

    #endregion

    #region Actions - Session editing

    /// Edits `space` for `operation`. The tab the issuing window shows decides
    /// only what that window shows next, which the result reports.
    public static SessionEditResult Evaluate(SessionOperation operation, SpaceState space, SessionEditArguments args,
        DateTimeOffset now, Guid? viewedTabId) {
        var edited = BrowserTabCollection.Restore(space);
        var selected = viewedTabId;
        int? index = args.Index;
        Guid? result = null;
        var selectSpace = false;
        var copies = new List<SessionTabCopy>();
        Guid? copiedGroup = null;
        Guid? sourceGroup = null;
        var changed = true;
        SessionFaviconUpdate? favicon = null;
        switch (operation) {
            case SessionOperation.TabPromoteTransient:
                if (args.Tab is { } transient) {
                    result = edited.PromoteTransient(transient, selected, now).Id;
                    selected = result;
                }
                selectSpace = true;
                break;
            case SessionOperation.TabArchiveTransient:
                edited.ArchiveTransient(args.RequiredTab, now);
                break;
            case SessionOperation.TabRestoreArchive:
                result = edited.RestoreArchived(args.RequiredTab, now).Id;
                selected = result;
                break;
            case SessionOperation.TabCloseDurable:
                selected = edited.CloseDurable(args.RequiredTabId, selected, args.FallbackTabId, args.ReturnToSavedUrl == true);
                break;
            case SessionOperation.TabCleanup:
                selected = edited.CleanupCurrentTabs(selected,
                    TimeSpan.FromSeconds(args.Lifetime ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput)), now, args.TabIds);
                break;
            case SessionOperation.TabOpen: {
                    var tab = BrowserTab.Restore(args.RequiredTab);
                    if (index is not null && args.After is not null) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                    edited.InsertTab(tab, args.After is { } origin ? edited.InsertionIndexAfter(origin) : index);
                    result = tab.Id;
                    if (args.Select == true) { selected = tab.Id; selectSpace = true; }
                    break;
                }
            case SessionOperation.TabCopy: {
                    var source = args.RequiredTabId;
                    var copy = edited.DuplicateTab(source, new SuppliedIds(args.RequiredIds), now,
                        args.Placement ?? TabPlacement.Current, index);
                    result = copy.Id;
                    if (args.Select != false) { selected = copy.Id; selectSpace = true; }
                    CopyPage(source, copy.Id);
                    break;
                }
            case SessionOperation.TabRename:
                var renamed = edited.Tab(args.RequiredTabId); var title = args.Title;
                changed = renamed.CustomTitle != (string.IsNullOrWhiteSpace(title) ? null : title.Trim());
                if (changed) renamed.Rename(title, now);
                break;
            case SessionOperation.TabObserve:
                changed = Observe(Target(args.TabId ?? selected));
                break;
            case SessionOperation.TabIcon:
                changed = SetIcon(Target(args.RequiredTabId));
                break;
            case SessionOperation.TabFaviconCache:
                changed = CacheFavicon(Target(args.RequiredTabId));
                break;
            case SessionOperation.TabSavedLocation:
                var located = Target(args.RequiredTabId);
                changed = located is not null && args.Action switch {
                    SavedLocationAction.Replace => located.ReplaceSavedLocation(),
                    SavedLocationAction.Restore => located.RestoreSavedLocation() is not null,
                    _ => throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit)
                };
                break;
            case SessionOperation.TabResidency:
                var resident = edited.Tab(args.RequiredTabId); var keep = args.Keep ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                changed = resident.KeepsPageLoaded != keep; resident.SetResidency(keep);
                break;
            case SessionOperation.TabMove:
                changed = edited.MoveTab(args.RequiredTabId, args.RequiredPlacement, args.FolderId, args.Before,
                    args.Detach == true, now);
                break;
            case SessionOperation.SplitOpenLink:
            case SessionOperation.SplitJoin: {
                    if (operation == SessionOperation.SplitOpenLink) {
                        var tab = BrowserTab.Restore(args.RequiredTab);
                        edited.InsertTab(tab, null);
                        args = args with { TabId = tab.Id }; result = tab.Id;
                    }
                    var target = edited.Tab(args.RequiredTargetId);
                    if (target.Placement.IsDurable) sourceGroup = target.SplitGroupId;
                    var joined = edited.JoinSplit(args.RequiredTabId, args.RequiredTargetId, index,
                        new SuppliedIds(args.RequiredIds), now);
                    selected = joined.SelectedTab; selectSpace = true;
                    copiedGroup = sourceGroup is not null && joined.Copies.Any(p => p.Source == target.Id)
                        ? edited.Tab(joined.SelectedTab).SplitGroupId : null;
                    foreach (var pair in joined.Copies)
                        CopyPage(pair.Source, pair.Copy);
                    break;
                }
            case SessionOperation.SplitJoinInPlace:
                changed = edited.JoinSplitInPlace(args.RequiredTabId, args.RequiredTargetId, index, args.RequiredGroupId, now);
                selected = args.RequiredTabId;
                break;
            case SessionOperation.SplitLeave:
                changed = edited.Tab(args.RequiredTabId).SplitGroupId is not null;
                edited.LeaveSplit(args.RequiredTabId, now);
                break;
            case SessionOperation.SplitReorder:
                changed = args.Offset is { } offset
                    ? edited.StepSplitMember(args.RequiredTabId, offset, now)
                    : edited.MoveSplitMember(args.RequiredTabId, index!.Value, now);
                break;
            case SessionOperation.SplitDissolve:
                changed = edited.DissolveSplit(args.RequiredGroupId, now);
                break;
            case SessionOperation.SplitMove:
                edited.MoveSplitGroup(args.RequiredGroupId, args.RequiredPlacement, args.FolderId, args.Before, now);
                break;
            case SessionOperation.FolderCreate:
                var createdFolder = args.RequiredFolderId;
                var createdTitle = args.Title;
                var createdPlacement = args.RequiredPlacement;
                edited.AddFolder(createdFolder, string.IsNullOrWhiteSpace(createdTitle) ? NewFolderTitle : createdTitle,
                    createdPlacement, args.ParentId);
                if (args.Color is { } color) edited.SetFolderColor(createdFolder, color);
                if (args.Symbol is { } symbol) edited.SetFolderSymbol(createdFolder, symbol);
                // Creating a folder around tabs is one transaction. Filing them
                // separately would publish a folder nobody asked to see empty,
                // and would leave it behind when the filing turned out invalid.
                if (args.TabIds is { Count: > 0 } members)
                    edited.FileTabs(members, createdPlacement, createdFolder, now, null, null, args.Detach == true);
                break;
            case SessionOperation.FolderColor:
                changed = edited.SetFolderColor(args.RequiredFolderId,
                    args.FolderColorValue ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput));
                break;
            case SessionOperation.FolderSymbol:
                changed = edited.SetFolderSymbol(args.RequiredFolderId,
                    args.FolderSymbolValue ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput));
                break;
            case SessionOperation.FolderRename:
                var folderId = args.RequiredFolderId;
                var folderTitle = (args.Title ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput)).Trim();
                if (folderTitle.Length == 0) folderTitle = UntitledFolderTitle;
                changed = edited.Folders.Single(f => f.Id == folderId).Title != folderTitle;
                if (changed) edited.RenameFolder(folderId, folderTitle);
                break;
            case SessionOperation.FolderCollapse:
                var collapsedId = args.RequiredFolderId; var collapsed = args.Collapsed ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                changed = edited.Folders.Single(f => f.Id == collapsedId).IsCollapsed != collapsed;
                if (changed) edited.CollapseFolder(collapsedId, collapsed, now);
                break;
            case SessionOperation.FolderDelete:
                edited.DeleteFolder(args.RequiredFolderId, now);
                break;
            case SessionOperation.FolderMove:
                edited.MoveFolder(args.RequiredFolderId, args.Placement, args.ParentId, now, args.BeforeFolderId, args.Before);
                break;
            case SessionOperation.TabsFile:
                edited.FileTabs(args.RequiredTabIds, args.RequiredPlacement, args.FolderId, now, args.Before, args.BeforeFolderId,
                    args.Detach == true);
                break;
            case SessionOperation.TabClose:
            case SessionOperation.TabDelete:
            case SessionOperation.TabClearCurrent: {
                    var deleting = operation == SessionOperation.TabDelete;
                    var clear = operation == SessionOperation.TabClearCurrent;
                    var ids = clear ? edited.Tabs.Where(t => !t.Placement.IsDurable).Select(t => t.Id).ToArray() : [args.RequiredTabId];
                    if (ids.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.NoCurrentTabs);
                    selected = edited.DismissTabs(ids, selected, args.FallbackTabId, now, deleting,
                        ensureSelection: deleting || clear, resetArchivePlacement: deleting || args.ResetArchivePlacement == true);
                    break;
                }
            default: throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit);
        }
        if (sourceGroup is { } oldGroup && copiedGroup is { } newGroup) edited.CopySplitMetadata(oldGroup, newGroup, now);
        if (operation is SessionOperation.TabClose or SessionOperation.TabDelete or SessionOperation.TabClearCurrent
            or SessionOperation.SplitJoin or SessionOperation.SplitOpenLink or SessionOperation.SplitJoinInPlace
            or SessionOperation.SplitLeave or SessionOperation.SplitDissolve
            || operation is SessionOperation.TabMove or SessionOperation.TabsFile && args.Detach == true)
            edited.PruneSplitMetadata();
        return new(edited, result, selected, selectSpace, copies, changed, favicon);

        BrowserTab? Target(Guid? id) => id is { } value ? edited.Tabs.FirstOrDefault(t => t.Id == value) : null;

        TabIconMode Mode(BrowserTab tab) => TabIconPolicy.Mode(tab.State.StoredIconMode, tab.State.Symbol);

        // The image itself stays in the native cache. The core names the tab
        // whose stored bytes the platform must now replace or drop.
        void Assign(Guid tab, bool adopts) => favicon = new SessionFaviconUpdate(tab, adopts);

        void ClearIconAssets(BrowserTab tab) {
            tab.SetFavicon(null, null);
            Assign(tab.Id, false);
        }

        // The page settled. A rename is not touched, a blank title is the page
        // saying nothing rather than clearing the name, and an automatic icon
        // follows the page while a chosen or pulled one does not.
        bool Observe(BrowserTab? tab) {
            if (tab is null) return false;
            var url = args.Url ?? tab.Url;
            var title = args.Title;
            var accent = args.IconAccent;
            var automatic = Mode(tab) == TabIconMode.Automatic;
            var updatesIcon = automatic && (args.FaviconChanged == true || tab.State.IconAccent != accent);
            if (url == tab.Url && Blank(title) == Blank(tab.Title) && !updatesIcon) return false;
            tab.ObserveAppearance(url, title);
            if (automatic && args.HasFavicon == true) {
                tab.SetFavicon(url, accent);
                Assign(tab.Id, true);
            }
            return true;
        }

        // Someone chose this tab's icon by hand, or handed it back to the page.
        bool SetIcon(BrowserTab? tab) {
            if (tab is null) return false;
            var mode = TabIconPolicy.RequireMode(args.Mode);
            if (mode == TabIconMode.Pulled && args.HasFavicon != true) return false;
            tab.SetIcon(mode == TabIconMode.Emoji ? TabIconPolicy.Symbol(args.Emoji) : TabIconPolicy.WebSymbol);
            if (mode == TabIconMode.Pulled) {
                tab.SetFavicon(tab.Url, args.IconAccent);
                Assign(tab.Id, true);
            } else ClearIconAssets(tab);
            tab.SetIconMode(mode);
            return true;
        }

        // A favicon that finished loading after the page moved on belongs to
        // the address it was captured from, not to whatever the tab shows now.
        bool CacheFavicon(BrowserTab? tab) {
            if (tab is null || Mode(tab) != TabIconMode.Automatic || args.HasFavicon != true) return false;
            var captured = args.Url ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
            if (!HistoryPolicy.SamePage(tab.Url, captured)) return false;
            tab.SetIcon(TabIconPolicy.WebSymbol);
            tab.SetFavicon(captured, args.IconAccent);
            Assign(tab.Id, true);
            return true;
        }

        void CopyPage(Guid source, Guid copy) {
            var observation = args.CopyObservations?.FirstOrDefault(item => item.TabId == source);
            var tab = edited.Tab(copy);
            if (tab.Content.IsWebPage && observation is not null)
                tab.AdoptObservation(observation.Url, observation.Title ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput));
            copies.Add(new SessionTabCopy(source, copy));
        }
    }

    private static string? Blank(string? value) => string.IsNullOrEmpty(value) ? null : value;

    #endregion
}
