using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Applies a domain edit to one compact Space projection. The native store
/// publishes the returned value atomically, then reconciles its live pages.
/// History, existing archive records and image payloads never cross this path.
public static class NativeSessionEditor {
    #region Variables

    public const int MaximumBytes = 4 * 1024 * 1024;

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

    public static byte[] Evaluate(ReadOnlySpan<byte> input) {
        var command = SessionEditRequest.Decode(input);
        var operation = command.Operation;
        var original = command.Space;
        var (document, state) = command.RestoreSpace();
        var space = BrowserTabCollection.Restore(state.Spaces.Single());
        // The viewed tab decides follow-up hints only; the result reports the
        // tab the window should show next and nothing stores it.
        var selected = command.ViewedTabId;
        var now = command.Now;
        var args = command.Arguments;
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
                    result = space.PromoteTransient(document.ReadNewTab(transient), selected, now).Id;
                    selected = result;
                }
                selectSpace = true;
                break;
            case SessionOperation.TabArchiveTransient:
                space.ArchiveTransient(document.ReadNewTab(args.RequiredTab), now);
                break;
            case SessionOperation.TabRestoreArchive:
                result = space.RestoreArchived(document.ReadNewTab(args.RequiredTab), now).Id;
                selected = result;
                break;
            case SessionOperation.TabCloseDurable:
                selected = space.CloseDurable(args.RequiredTabId, selected, args.FallbackTabId,
                    args.ReturnToSavedUrl == true);
                break;
            case SessionOperation.TabCleanup:
                selected = space.CleanupCurrentTabs(selected, TimeSpan.FromSeconds(args.Lifetime ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput)), now,
                    args.TabIds);
                break;
            case SessionOperation.TabOpen: {
                    var supplied = args.RequiredTab;
                    var tab = BrowserTab.Restore(document.ReadNewTab(supplied));
                    if (index is not null && args.After is not null) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                    space.InsertTab(tab, args.After is { } origin ? space.InsertionIndexAfter(origin) : index);
                    result = tab.Id;
                    if (args.Select == true) { selected = tab.Id; selectSpace = true; }
                    break;
                }
            case SessionOperation.TabTouch:
                // Records when the person last looked at a tab, which drives
                // cleanup. Showing it is the window's own selection change.
                var touchedTabId = args.RequiredTabId;
                space.Tab(touchedTabId).Activate(now); result = touchedTabId;
                break;
            case SessionOperation.TabCopy: {
                    var source = args.RequiredTabId;
                    var copy = space.DuplicateTab(source, new SuppliedIds(args.RequiredIds), now,
                        args.Placement ?? TabPlacement.Current, index);
                    result = copy.Id;
                    if (args.Select != false) { selected = copy.Id; selectSpace = true; }
                    CopyPage(source, copy.Id);
                    break;
                }
            case SessionOperation.TabRename:
                var renamed = space.Tab(args.RequiredTabId); var title = args.Title;
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
                var resident = space.Tab(args.RequiredTabId); var keep = args.Keep ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                changed = resident.KeepsPageLoaded != keep; resident.SetResidency(keep);
                break;
            case SessionOperation.TabMove:
                changed = space.MoveTab(args.RequiredTabId, args.RequiredPlacement, args.FolderId, args.Before,
                    args.Detach == true, now);
                break;
            case SessionOperation.SplitOpenLink:
            case SessionOperation.SplitJoin: {
                    if (operation == SessionOperation.SplitOpenLink) {
                        var tab = BrowserTab.Restore(document.ReadNewTab(args.RequiredTab));
                        space.InsertTab(tab, null);
                        args = args with { TabId = tab.Id }; result = tab.Id;
                    }
                    var target = space.Tab(args.RequiredTargetId);
                    if (target.Placement != TabPlacement.Current) sourceGroup = target.SplitGroupId;
                    var joined = space.JoinSplit(args.RequiredTabId, args.RequiredTargetId, index,
                        new SuppliedIds(args.RequiredIds), now);
                    selected = joined.SelectedTab; selectSpace = true;
                    copiedGroup = sourceGroup is not null && joined.Copies.Any(p => p.Source == target.Id)
                        ? space.Tab(joined.SelectedTab).SplitGroupId : null;
                    foreach (var pair in joined.Copies)
                        CopyPage(pair.Source, pair.Copy);
                    break;
                }
            case SessionOperation.SplitJoinInPlace:
                changed = space.JoinSplitInPlace(args.RequiredTabId, args.RequiredTargetId, index, args.RequiredGroupId, now);
                selected = args.RequiredTabId;
                break;
            case SessionOperation.SplitLeave:
                changed = space.Tab(args.RequiredTabId).SplitGroupId is not null;
                space.LeaveSplit(args.RequiredTabId, now);
                break;
            case SessionOperation.SplitReorder:
                changed = args.Offset is { } offset
                    ? space.StepSplitMember(args.RequiredTabId, offset, now)
                    : space.MoveSplitMember(args.RequiredTabId, index!.Value, now);
                break;
            case SessionOperation.SplitDissolve:
                changed = space.DissolveSplit(args.RequiredGroupId, now);
                break;
            case SessionOperation.SplitMove:
                space.MoveSplitGroup(args.RequiredGroupId, args.RequiredPlacement,
                    args.FolderId, args.Before, now);
                break;
            case SessionOperation.FolderCreate:
                var createdFolder = args.RequiredFolderId;
                var createdTitle = args.Title;
                var createdPlacement = args.RequiredPlacement;
                space.AddFolder(createdFolder, string.IsNullOrWhiteSpace(createdTitle) ? "New Folder" : createdTitle,
                    createdPlacement, args.ParentId);
                if (args.Color is { } color) document.SetFolderMetadata(createdFolder, "color", color);
                if (args.Symbol is { } symbol) document.SetFolderMetadata(createdFolder, "symbol", FolderSymbol(symbol));
                // Creating a folder around tabs is one transaction. Filing them
                // separately would publish a folder nobody asked to see empty,
                // and would leave it behind when the filing turned out invalid.
                if (args.TabIds is { Count: > 0 } members)
                    space.FileTabs(members,
                        createdPlacement, createdFolder, now, null, null, args.Detach == true);
                break;
            case SessionOperation.FolderColor:
            case SessionOperation.FolderSymbol:
                var styledFolder = args.RequiredFolderId;
                if (!space.Folders.Any(f => f.Id == styledFolder)) throw new BrowserRuleException(BrowserRuleCodes.UnknownFolder);
                var isColor = operation == SessionOperation.FolderColor;
                var field = isColor ? "color" : "symbol";
                changed = document.SetFolderMetadata(styledFolder, field,
                    isColor ? args.FolderColorValue ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput)
                        : FolderSymbol(args.FolderSymbolValue ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput)));
                break;
            case SessionOperation.FolderRename:
                var folderId = args.RequiredFolderId;
                var folderTitle = (args.Title ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput)).Trim();
                if (folderTitle.Length == 0) folderTitle = "Untitled Folder";
                changed = space.Folders.Single(f => f.Id == folderId).Name != folderTitle;
                if (changed) space.RenameFolder(folderId, folderTitle);
                break;
            case SessionOperation.FolderCollapse:
                var collapsedId = args.RequiredFolderId; var collapsed = args.Collapsed ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                changed = space.Folders.Single(f => f.Id == collapsedId).IsCollapsed != collapsed;
                if (changed) space.CollapseFolder(collapsedId, collapsed, now);
                break;
            case SessionOperation.FolderDelete:
                space.DeleteFolder(args.RequiredFolderId, now);
                break;
            case SessionOperation.FolderMove:
                space.MoveFolder(args.RequiredFolderId, args.Placement, args.ParentId, now,
                    args.BeforeFolderId, args.Before);
                break;
            case SessionOperation.TabsFile:
                space.FileTabs(args.RequiredTabIds,
                    args.RequiredPlacement, args.FolderId, now, args.Before, args.BeforeFolderId,
                    args.Detach == true);
                break;
            case SessionOperation.TabClose:
            case SessionOperation.TabDelete:
            case SessionOperation.TabClearCurrent: {
                    var deleting = operation == SessionOperation.TabDelete;
                    var clear = operation == SessionOperation.TabClearCurrent;
                    var ids = clear ? space.Tabs.Where(t => t.Placement == TabPlacement.Current).Select(t => t.Id).ToArray() : [args.RequiredTabId];
                    if (ids.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.NoCurrentTabs);
                    selected = space.DismissTabs(ids, selected, args.FallbackTabId, now, deleting,
                        ensureSelection: deleting || clear, resetArchivePlacement: deleting || args.ResetArchivePlacement == true);
                    break;
                }
            default: throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit);
        }
        var next = state with { Spaces = [space.Capture(state.Spaces[0])] };
        var output = document.Write(next)["session"]!["spaces"]![0]!.DeepClone();
        if (sourceGroup is { } oldGroup && copiedGroup is { } newGroup
            && original["splitGroups"] is JsonArray originalGroups
            && originalGroups.FirstOrDefault(g => NativeSessionAuthority.Id(g!["id"]) == oldGroup) is { } metadata) {
            var copy = metadata.DeepClone();
            copy["id"] = new JsonObject { ["rawValue"] = newGroup.ToString() };
            foreach (var field in new[] { "titleModifiedAt", "iconModifiedAt", "tintModifiedAt" })
                copy[field] = NativeEditTimestamp.Encode(now);
            if (output["splitGroups"] is not JsonArray) output["splitGroups"] = new JsonArray();
            output["splitGroups"]!.AsArray().Add(copy);
        }
        bool prunesGroups = operation is SessionOperation.TabClose or SessionOperation.TabDelete or SessionOperation.TabClearCurrent or SessionOperation.SplitJoin or SessionOperation.SplitOpenLink
            or SessionOperation.SplitJoinInPlace or SessionOperation.SplitLeave or SessionOperation.SplitDissolve
            || operation is SessionOperation.TabMove or SessionOperation.TabsFile && args.Detach == true;
        if (prunesGroups && output["splitGroups"] is JsonArray groups) {
            var retained = space.Tabs.Where(t => t.SplitGroupId is not null).Select(t => t.SplitGroupId!.Value).ToHashSet();
            for (int i = groups.Count - 1; i >= 0; i--)
                if (!retained.Contains(LegacySessionDocument.Id(groups[i]!["id"]))) groups.RemoveAt(i);
        }
        // Archives are new records only; their images remain in the native cache.
        foreach (var archived in output["archivedTabs"]!.AsArray()) archived!["tab"]!.AsObject().Remove("faviconData");
        return new SessionEditResult(output, result, selected, selectSpace, copies, changed, favicon).Encode();

        BrowserTab? Target(Guid? id) => id is { } value ? space.Tabs.FirstOrDefault(t => t.Id == value) : null;

        string Mode(BrowserTab tab) => TabIconPolicy.Mode(
            document.TabMetadata(tab.Id, "storedIconMode")?.GetValue<string>(),
            document.TabMetadata(tab.Id, "symbol")?.GetValue<string>());

        // The image itself stays in the native cache. The core names the tab
        // whose stored bytes the platform must now replace or drop.
        void Assign(Guid tab, bool adopts) => favicon = new SessionFaviconUpdate(tab, adopts);

        void ClearIconAssets(BrowserTab tab) {
            document.SetTabMetadata(tab.Id, "faviconURL", null);
            document.SetTabMetadata(tab.Id, "iconAccent", null);
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
            var automatic = Mode(tab) == TabIconPolicy.Automatic;
            var updatesIcon = automatic && (args.FaviconChanged == true
                || !JsonNode.DeepEquals(document.TabMetadata(tab.Id, "iconAccent"), accent));
            if (url == tab.Url && Blank(title) == Blank(tab.Title) && !updatesIcon) return false;
            tab.ObserveAppearance(url, title);
            if (automatic && args.HasFavicon == true) {
                document.SetTabMetadata(tab.Id, "faviconURL", url is null ? null : JsonValue.Create(url));
                document.SetTabMetadata(tab.Id, "iconAccent", accent);
                Assign(tab.Id, true);
            }
            return true;
        }

        // Someone chose this tab's icon by hand, or handed it back to the page.
        bool SetIcon(BrowserTab? tab) {
            if (tab is null) return false;
            var mode = TabIconPolicy.RequireMode(args.Mode);
            if (mode == TabIconPolicy.Pulled && args.HasFavicon != true) return false;
            document.SetTabMetadata(tab.Id, "symbol", mode == TabIconPolicy.Emoji
                ? TabIconPolicy.Symbol(args.Emoji) : TabIconPolicy.WebSymbol);
            if (mode == TabIconPolicy.Pulled) {
                document.SetTabMetadata(tab.Id, "faviconURL", tab.Url is null ? null : JsonValue.Create(tab.Url));
                document.SetTabMetadata(tab.Id, "iconAccent", args.IconAccent);
                Assign(tab.Id, true);
            } else ClearIconAssets(tab);
            document.SetTabMetadata(tab.Id, "storedIconMode", mode);
            return true;
        }

        // A favicon that finished loading after the page moved on belongs to
        // the address it was captured from, not to whatever the tab shows now.
        bool CacheFavicon(BrowserTab? tab) {
            if (tab is null || Mode(tab) != TabIconPolicy.Automatic
                || args.HasFavicon != true) return false;
            var captured = args.Url ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
            if (!HistoryPolicy.SamePage(tab.Url, captured)) return false;
            document.SetTabMetadata(tab.Id, "symbol", TabIconPolicy.WebSymbol);
            document.SetTabMetadata(tab.Id, "faviconURL", captured);
            document.SetTabMetadata(tab.Id, "iconAccent", args.IconAccent);
            Assign(tab.Id, true);
            return true;
        }

        void CopyPage(Guid source, Guid copy) {
            document.CopyTabMetadata(source, copy);
            var observation = args.CopyObservations?.FirstOrDefault(item => item.TabId == source);
            var tab = space.Tab(copy);
            if (tab.Content.IsWebPage && observation is not null)
                tab.Observe(observation.Url, observation.Title ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput), false, false, false, null);
            copies.Add(new SessionTabCopy(source, copy));
        }
    }

    private static string? Blank(string? value) => string.IsNullOrEmpty(value) ? null : value;

    private static JsonNode FolderSymbol(string symbol) {
        if (symbol.Length == 0 || Encoding.UTF8.GetByteCount(symbol) > 128) throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderSymbol);
        return JsonValue.Create(symbol)!;
    }

    #endregion
}
