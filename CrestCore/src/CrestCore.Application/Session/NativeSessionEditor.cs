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
    private static readonly DateTimeOffset SwiftEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private sealed class SuppliedIds(JsonArray values) : IIdSource {
        #region Variables

        private readonly Queue<Guid> values = new(values.Select(n => Guid.Parse(n!.GetValue<string>())));

        #endregion

        #region Actions - Identity supply

        public Guid Next() => values.Dequeue();

        #endregion
    }

    #endregion

    #region Actions - Session editing

    public static byte[] Evaluate(ReadOnlySpan<byte> input) {
        if (input.Length > MaximumBytes) throw new ProtocolException(ProtocolErrorCodes.SessionEditLimit);
        var parsed = Protocol.Parse(input);
        if (parsed.GetProperty("version").GetInt32() != 1) throw new ProtocolException(ProtocolErrorCodes.VersionMismatch);
        var request = JsonNode.Parse(input)!.AsObject();
        var operation = Protocol.Text(parsed, "operation");
        var original = request["space"]!.AsObject();
        var session = new JsonObject { ["spaces"] = new JsonArray(original.DeepClone()), ["selectedSpaceID"] = original["id"]!.DeepClone() };
        var document = new LegacySessionDocument(new() { ["session"] = session });
        var state = document.Read(new SystemIdSource());
        var space = BrowserTabCollection.Restore(state.Spaces.Single());
        var selected = state.Spaces[0].SelectedTabId;
        var now = SwiftEpoch.AddSeconds(parsed.GetProperty("now").GetDouble());
        var args = request["arguments"]!.AsObject();
        TabId Id(string name) => new(Guid.Parse(args[name]!.GetValue<string>()));
        TabId? OptionalId(string name) => args[name] is null ? null : Id(name);
        int? index = args["index"]?.GetValue<int>();
        TabId? result = null;
        var selectSpace = false;
        var copies = new JsonArray();
        Guid? copiedGroup = null;
        Guid? sourceGroup = null;
        var changed = true;
        JsonObject? favicon = null;
        FolderId? Folder(string name) => args[name] is null ? null : new(Guid.Parse(args[name]!.GetValue<string>()));
        TabPlacement Placement(string name) => Enum.Parse<TabPlacement>(args[name]!.GetValue<string>(), true);
        switch (operation) {
            case "tab.promote_transient":
                if (args["tab"] is JsonObject transient) {
                    result = space.PromoteTransient(document.ReadNewTab(transient), selected, now).Id;
                    selected = result;
                }
                selectSpace = true;
                break;
            case "tab.archive_transient":
                space.ArchiveTransient(document.ReadNewTab(args["tab"]!.AsObject()), now);
                break;
            case "tab.restore_archive":
                result = space.RestoreArchived(document.ReadNewTab(args["tab"]!.AsObject()), now).Id;
                selected = result;
                break;
            case "tab.close_durable":
                selected = space.CloseDurable(Id("tabId"), selected, OptionalId("fallbackTabId"),
                    args["returnToSavedURL"]!.GetValue<bool>());
                break;
            case "tab.cleanup":
                selected = space.CleanupCurrentTabs(selected, TimeSpan.FromSeconds(args["lifetime"]!.GetValue<double>()), now);
                break;
            case "tab.open": {
                    var supplied = args["tab"]!.AsObject();
                    var tab = BrowserTab.Restore(document.ReadNewTab(supplied));
                    space.InsertTab(tab, index);
                    result = tab.Id;
                    if (args["select"]!.GetValue<bool>()) { selected = tab.Id; selectSpace = true; }
                    break;
                }
            case "tab.activate":
                result = Id("tabId"); space.Tab(result.Value).Activate(now); selected = result; selectSpace = true;
                break;
            case "tab.copy": {
                    var source = Id("tabId");
                    var copy = space.DuplicateTab(source, new SuppliedIds(args["ids"]!.AsArray()), now,
                        args["placement"] is null ? TabPlacement.Current : Placement("placement"), index);
                    result = copy.Id;
                    if (args["select"]?.GetValue<bool>() != false) { selected = copy.Id; selectSpace = true; }
                    CopyPage(source, copy.Id);
                    break;
                }
            case "tab.rename":
                var renamed = space.Tab(Id("tabId")); var title = args["title"]?.GetValue<string>();
                changed = renamed.CustomTitle != (string.IsNullOrWhiteSpace(title) ? null : title.Trim());
                if (changed) renamed.Rename(title, now);
                break;
            case "tab.observe":
                changed = Observe(Target(args["tabId"] is null ? selected : Id("tabId")));
                break;
            case "tab.icon":
                changed = SetIcon(Target(Id("tabId")));
                break;
            case "tab.favicon.cache":
                changed = CacheFavicon(Target(Id("tabId")));
                break;
            case "tab.saved_location":
                var located = Target(Id("tabId"));
                changed = located is not null && args["action"]!.GetValue<string>() switch {
                    "replace" => located.ReplaceSavedLocation(),
                    "restore" => located.RestoreSavedLocation() is not null,
                    _ => throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit)
                };
                break;
            case "tab.residency":
                var resident = space.Tab(Id("tabId")); var keep = args["keep"]!.GetValue<bool>();
                changed = resident.KeepsPageLoaded != keep; resident.SetResidency(keep);
                break;
            case "tab.move":
                changed = space.MoveTab(Id("tabId"), Placement("placement"), Folder("folderId"), OptionalId("before"),
                    args["detach"]!.GetValue<bool>(), now);
                break;
            case "split.open_link":
            case "split.join": {
                    if (operation == "split.open_link") {
                        var tab = BrowserTab.Restore(document.ReadNewTab(args["tab"]!.AsObject()));
                        space.InsertTab(tab, null);
                        args["tabId"] = tab.Id.Value.ToString(); result = tab.Id;
                    }
                    var target = space.Tab(Id("targetId"));
                    if (target.Placement != TabPlacement.Current) sourceGroup = target.SplitGroupId;
                    var joined = space.JoinSplit(Id("tabId"), Id("targetId"), index,
                        new SuppliedIds(args["ids"]!.AsArray()), now);
                    selected = joined.SelectedTab; selectSpace = true;
                    copiedGroup = sourceGroup is not null && joined.Copies.Any(p => p.Source == target.Id)
                        ? space.Tab(joined.SelectedTab).SplitGroupId : null;
                    foreach (var pair in joined.Copies)
                        CopyPage(pair.Source, pair.Copy);
                    break;
                }
            case "split.join_in_place":
                changed = space.JoinSplitInPlace(Id("tabId"), Id("targetId"), index, Guid.Parse(args["groupId"]!.GetValue<string>()), now);
                selected = Id("tabId");
                break;
            case "split.leave":
                changed = space.Tab(Id("tabId")).SplitGroupId is not null;
                space.LeaveSplit(Id("tabId"), now);
                break;
            case "split.reorder":
                changed = args["offset"] is { } offset
                    ? space.StepSplitMember(Id("tabId"), offset.GetValue<int>(), now)
                    : space.MoveSplitMember(Id("tabId"), index!.Value, now);
                break;
            case "split.dissolve":
                changed = space.DissolveSplit(Guid.Parse(args["groupId"]!.GetValue<string>()), now);
                break;
            case "split.move":
                space.MoveSplitGroup(Guid.Parse(args["groupId"]!.GetValue<string>()), Placement("placement"),
                    Folder("folderId"), OptionalId("before"), now);
                break;
            case "folder.create":
                var createdFolder = Folder("folderId")!.Value;
                var createdTitle = args["title"]?.GetValue<string>();
                var createdPlacement = Placement("placement");
                space.AddFolder(createdFolder, string.IsNullOrWhiteSpace(createdTitle) ? "New Folder" : createdTitle,
                    createdPlacement, Folder("parentId"));
                if (args["color"] is { } color) document.SetFolderMetadata(createdFolder, "color", color.AsObject());
                if (args["symbol"] is { } symbol) document.SetFolderMetadata(createdFolder, "symbol", FolderSymbol(symbol));
                // Creating a folder around tabs is one transaction. Filing them
                // separately would publish a folder nobody asked to see empty,
                // and would leave it behind when the filing turned out invalid.
                if (args["tabIds"] is JsonArray members && members.Count > 0)
                    space.FileTabs(members.Select(n => new TabId(Guid.Parse(n!.GetValue<string>()))).ToArray(),
                        createdPlacement, createdFolder, now, null, null, args["detach"]?.GetValue<bool>() == true);
                break;
            case "folder.color":
            case "folder.symbol":
                var styledFolder = Folder("folderId")!.Value;
                if (!space.Folders.Any(f => f.Id == styledFolder)) throw new BrowserRuleException(BrowserRuleCodes.UnknownFolder);
                var field = operation == "folder.color" ? "color" : "symbol";
                changed = document.SetFolderMetadata(styledFolder, field,
                    field == "color" ? args["value"]!.AsObject() : FolderSymbol(args["value"]!));
                break;
            case "folder.rename":
                var folderId = Folder("folderId")!.Value; var folderTitle = args["title"]!.GetValue<string>().Trim();
                if (folderTitle.Length == 0) folderTitle = "Untitled Folder";
                changed = space.Folders.Single(f => f.Id == folderId).Name != folderTitle;
                if (changed) space.RenameFolder(folderId, folderTitle);
                break;
            case "folder.collapse":
                var collapsedId = Folder("folderId")!.Value; var collapsed = args["collapsed"]!.GetValue<bool>();
                changed = space.Folders.Single(f => f.Id == collapsedId).IsCollapsed != collapsed;
                if (changed) space.CollapseFolder(collapsedId, collapsed, now);
                break;
            case "folder.delete":
                space.DeleteFolder(Folder("folderId")!.Value, now);
                break;
            case "folder.move":
                space.MoveFolder(Folder("folderId")!.Value, args["placement"] is null ? null : Placement("placement"), Folder("parentId"), now,
                    Folder("beforeFolderId"), OptionalId("before"));
                break;
            case "tabs.file":
                space.FileTabs(args["tabIds"]!.AsArray().Select(n => new TabId(Guid.Parse(n!.GetValue<string>()))).ToArray(),
                    Placement("placement"), Folder("folderId"), now, OptionalId("before"), Folder("beforeFolderId"),
                    args["detach"]!.GetValue<bool>());
                break;
            case "tab.close":
            case "tab.delete":
            case "tab.clear_current": {
                    var deleting = operation == "tab.delete";
                    var clear = operation == "tab.clear_current";
                    var ids = clear ? space.Tabs.Where(t => t.Placement == TabPlacement.Current).Select(t => t.Id).ToArray() : [Id("tabId")];
                    if (ids.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.NoCurrentTabs);
                    selected = space.DismissTabs(ids, selected, OptionalId("fallbackTabId"), now, deleting,
                        ensureSelection: deleting || clear, resetArchivePlacement: deleting || args["resetArchivePlacement"]?.GetValue<bool>() == true);
                    break;
                }
            default: throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit);
        }
        var next = state with { Spaces = [space.Capture(state.Spaces[0], selected)] };
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
        bool prunesGroups = operation is "tab.close" or "tab.delete" or "tab.clear_current" or "split.join" or "split.open_link"
            or "split.join_in_place" or "split.leave" or "split.dissolve"
            || operation is "tab.move" or "tabs.file" && args["detach"]?.GetValue<bool>() == true;
        if (prunesGroups && output["splitGroups"] is JsonArray groups) {
            var retained = space.Tabs.Where(t => t.SplitGroupId is not null).Select(t => t.SplitGroupId!.Value).ToHashSet();
            for (int i = groups.Count - 1; i >= 0; i--)
                if (!retained.Contains(Guid.Parse(groups[i]!["id"]!["rawValue"]!.GetValue<string>()))) groups.RemoveAt(i);
        }
        // Archives are new records only; their images remain in the native cache.
        foreach (var archived in output["archivedTabs"]!.AsArray()) archived!["tab"]!.AsObject().Remove("faviconData");
        return Encoding.UTF8.GetBytes(new JsonObject {
            ["space"] = output,
            ["tabId"] = result?.Value.ToString(),
            ["selectSpace"] = selectSpace,
            ["copies"] = copies,
            ["changed"] = changed,
            ["favicon"] = favicon
        }.ToJsonString());

        BrowserTab? Target(TabId? id) => id is { } value ? space.Tabs.FirstOrDefault(t => t.Id == value) : null;

        string Mode(BrowserTab tab) => TabIconPolicy.Mode(
            document.TabMetadata(tab.Id, "storedIconMode")?.GetValue<string>(),
            document.TabMetadata(tab.Id, "symbol")?.GetValue<string>());

        // The image itself stays in the native cache. The core names the tab
        // whose stored bytes the platform must now replace or drop.
        void Assign(TabId tab, bool adopts)
            => favicon = new JsonObject { ["tabId"] = tab.Value.ToString(), ["adopts"] = adopts };

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
            var url = args["url"]?.GetValue<string>() ?? tab.Url;
            var title = args["title"]?.GetValue<string>();
            var accent = args["iconAccent"];
            var automatic = Mode(tab) == TabIconPolicy.Automatic;
            var updatesIcon = automatic && (args["faviconChanged"]?.GetValue<bool>() == true
                || !JsonNode.DeepEquals(document.TabMetadata(tab.Id, "iconAccent"), accent));
            if (url == tab.Url && Blank(title) == Blank(tab.Title) && !updatesIcon) return false;
            tab.ObserveAppearance(url, title);
            if (automatic && args["hasFavicon"]?.GetValue<bool>() == true) {
                document.SetTabMetadata(tab.Id, "faviconURL", url is null ? null : JsonValue.Create(url));
                document.SetTabMetadata(tab.Id, "iconAccent", accent);
                Assign(tab.Id, true);
            }
            return true;
        }

        // Someone chose this tab's icon by hand, or handed it back to the page.
        bool SetIcon(BrowserTab? tab) {
            if (tab is null) return false;
            var mode = TabIconPolicy.RequireMode(args["mode"]?.GetValue<string>());
            if (mode == TabIconPolicy.Pulled && args["hasFavicon"]?.GetValue<bool>() != true) return false;
            document.SetTabMetadata(tab.Id, "symbol", mode == TabIconPolicy.Emoji
                ? TabIconPolicy.Symbol(args["emoji"]?.GetValue<string>()) : TabIconPolicy.WebSymbol);
            if (mode == TabIconPolicy.Pulled) {
                document.SetTabMetadata(tab.Id, "faviconURL", tab.Url is null ? null : JsonValue.Create(tab.Url));
                document.SetTabMetadata(tab.Id, "iconAccent", args["iconAccent"]);
                Assign(tab.Id, true);
            } else ClearIconAssets(tab);
            document.SetTabMetadata(tab.Id, "storedIconMode", mode);
            return true;
        }

        // A favicon that finished loading after the page moved on belongs to
        // the address it was captured from, not to whatever the tab shows now.
        bool CacheFavicon(BrowserTab? tab) {
            if (tab is null || Mode(tab) != TabIconPolicy.Automatic
                || args["hasFavicon"]?.GetValue<bool>() != true) return false;
            var captured = args["url"]!.GetValue<string>();
            if (!HistoryPolicy.SamePage(tab.Url, captured)) return false;
            document.SetTabMetadata(tab.Id, "symbol", TabIconPolicy.WebSymbol);
            document.SetTabMetadata(tab.Id, "faviconURL", captured);
            document.SetTabMetadata(tab.Id, "iconAccent", args["iconAccent"]);
            Assign(tab.Id, true);
            return true;
        }

        void CopyPage(TabId source, TabId copy) {
            document.CopyTabMetadata(source, copy);
            var observation = (args["copyObservations"] as JsonArray)?.FirstOrDefault(o =>
                NativeSessionAuthority.Id(o!["tabId"]) == source.Value);
            var tab = space.Tab(copy);
            if (tab.Content.IsWebPage && observation is not null)
                tab.Observe(observation["url"]?.GetValue<string>(), observation["title"]!.GetValue<string>(), false, false, false, null);
            copies.Add((JsonNode)new JsonObject { ["source"] = source.Value.ToString(), ["copy"] = copy.Value.ToString() });
        }
    }

    private static string? Blank(string? value) => string.IsNullOrEmpty(value) ? null : value;

    private static JsonNode FolderSymbol(JsonNode value) {
        string symbol = value.GetValue<string>();
        if (symbol.Length == 0 || Encoding.UTF8.GetByteCount(symbol) > 128) throw new BrowserRuleException(BrowserRuleCodes.InvalidFolderSymbol);
        return JsonValue.Create(symbol)!;
    }

    #endregion
}
