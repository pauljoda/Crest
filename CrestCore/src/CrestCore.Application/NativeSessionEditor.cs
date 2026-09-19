using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Applies a domain edit to one compact Space projection. The native store
/// publishes the returned value atomically, then reconciles its live pages.
/// History, existing archive records and image payloads never cross this path.
public static class NativeSessionEditor
{
    public const int MaximumBytes = 4 * 1024 * 1024;
    private static readonly DateTimeOffset SwiftEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    public static byte[] Evaluate(ReadOnlySpan<byte> input)
    {
        if (input.Length > MaximumBytes) throw new ProtocolException("session_edit_limit");
        var parsed = Protocol.Parse(input);
        if (parsed.GetProperty("version").GetInt32() != 1) throw new ProtocolException("version_mismatch");
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
        var changed = true;
        FolderId? Folder(string name) => args[name] is null ? null : new(Guid.Parse(args[name]!.GetValue<string>()));
        TabPlacement Placement(string name) => Enum.Parse<TabPlacement>(args[name]!.GetValue<string>(), true);
        switch (operation)
        {
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
            case "tab.open":
            case "tab.duplicate":
            {
                var supplied = args["tab"]!.AsObject();
                var tab = BrowserTab.Restore(document.ReadNewTab(supplied));
                space.InsertTab(tab, index, operation == "tab.duplicate");
                result = tab.Id;
                if (args["select"]!.GetValue<bool>()) { selected = tab.Id; selectSpace = true; }
                break;
            }
            case "tab.activate":
                result = Id("tabId"); space.Tab(result.Value).Activate(now); selected = result; selectSpace = true;
                break;
            case "tab.rename":
                var renamed = space.Tab(Id("tabId")); var title = args["title"]?.GetValue<string>();
                changed = renamed.CustomTitle != (string.IsNullOrWhiteSpace(title) ? null : title.Trim());
                if (changed) renamed.Rename(title, now);
                break;
            case "tab.residency":
                var resident = space.Tab(Id("tabId")); var keep = args["keep"]!.GetValue<bool>();
                changed = resident.KeepsPageLoaded != keep; resident.SetResidency(keep);
                break;
            case "tab.move":
                changed = space.MoveTab(Id("tabId"), Placement("placement"), Folder("folderId"), OptionalId("before"),
                    args["detach"]!.GetValue<bool>(), now);
                break;
            case "split.join":
                var joined = space.JoinSplit(Id("tabId"), Id("targetId"), index,
                    new SuppliedIds(args["ids"]!.AsArray()), now);
                selected = joined.SelectedTab; selectSpace = true;
                foreach (var pair in joined.Copies)
                {
                    document.CopyTabMetadata(pair.Source, pair.Copy);
                    copies.Add((JsonNode)new JsonObject { ["source"] = pair.Source.Value.ToString(), ["copy"] = pair.Copy.Value.ToString() });
                }
                break;
            case "split.join_in_place":
                changed = space.JoinSplitInPlace(Id("tabId"), Id("targetId"), index, Guid.Parse(args["groupId"]!.GetValue<string>()), now);
                selected = Id("tabId");
                break;
            case "split.leave":
                changed = space.Tab(Id("tabId")).SplitGroupId is not null;
                space.LeaveSplit(Id("tabId"), now);
                break;
            case "split.reorder":
                changed = space.MoveSplitMember(Id("tabId"), index!.Value, now);
                break;
            case "folder.create":
                space.AddFolder(Folder("folderId")!.Value, args["title"]!.GetValue<string>(), Placement("placement"), Folder("parentId"));
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
            case "tab.clear_current":
            {
                var deleting = operation == "tab.delete";
                var clear = operation == "tab.clear_current";
                var ids = clear ? space.Tabs.Where(t => t.Placement == TabPlacement.Current).Select(t => t.Id).ToArray() : [Id("tabId")];
                if (ids.Length == 0) throw new BrowserRuleException("no_current_tabs");
                selected = space.DismissTabs(ids, selected, OptionalId("fallbackTabId"), now, deleting,
                    ensureSelection: deleting || clear, resetArchivePlacement: deleting || args["resetArchivePlacement"]?.GetValue<bool>() == true);
                break;
            }
            default: throw new ProtocolException("unknown_session_edit");
        }
        var next = state with { Spaces = [space.Capture(state.Spaces[0], selected)] };
        var output = document.Write(next)["session"]!["spaces"]![0]!.DeepClone();
        bool prunesGroups = operation is "tab.close" or "tab.delete" or "tab.clear_current" or "split.join" or "split.join_in_place" or "split.leave"
            || operation is "tab.move" or "tabs.file" && args["detach"]?.GetValue<bool>() == true;
        if (prunesGroups && output["splitGroups"] is JsonArray groups)
        {
            var retained = space.Tabs.Where(t => t.SplitGroupId is not null).Select(t => t.SplitGroupId!.Value).ToHashSet();
            for (int i = groups.Count - 1; i >= 0; i--)
                if (!retained.Contains(Guid.Parse(groups[i]!["id"]!["rawValue"]!.GetValue<string>()))) groups.RemoveAt(i);
        }
        // Archives are new records only; their images remain in the native cache.
        foreach (var archived in output["archivedTabs"]!.AsArray()) archived!["tab"]!.AsObject().Remove("faviconData");
        return Encoding.UTF8.GetBytes(new JsonObject
        { ["space"] = output, ["tabId"] = result?.Value.ToString(), ["selectSpace"] = selectSpace,
            ["copies"] = copies, ["changed"] = changed }.ToJsonString());
    }
    private sealed class SuppliedIds(JsonArray values) : IIdSource
    {
        private readonly Queue<Guid> values = new(values.Select(n => Guid.Parse(n!.GetValue<string>())));
        public Guid Next() => values.Dequeue();
    }
}
