using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Projects the native checkpoint format onto the existing CloudKit payload
/// format. Wire encoding lives here; portable-content and ordering rules are domain rules.
public static class NativeSyncProjection {
    #region Actions - Projection

    internal static Guid Id(JsonNode? value) => NativeSessionAuthority.Id(value);

    internal static string? Text(JsonNode? value) => value?.GetValue<string>();

    internal static JsonArray Items(JsonNode value, string field) => value[field]?.AsArray() ?? [];

    internal static JsonObject Fields(JsonNode source, params string[] names)
        => new(names.Where(n => source[n] is not null).Select(n => new KeyValuePair<string, JsonNode?>(n, source[n]!.DeepClone())));

    internal static TabPlacement Placement(JsonNode value, string field = "placement")
        => Text(value[field]) switch {
            "current" => TabPlacement.Current,
            "saved" => TabPlacement.Saved,
            "pinned" => TabPlacement.Pinned,
            _ => throw new BrowserRuleException("invalid_sync_placement")
        };

    internal static string? SavedUrl(JsonNode tab) => Text(tab["savedURL"])
        ?? (Placement(tab) == TabPlacement.Current ? null : Text(tab["url"]));

    internal static bool PortableTab(JsonNode tab) => SyncContentPolicy.IncludesTab(Text(tab["url"]), tab["nativeContent"] is not null, SavedUrl(tab));

    internal static string ArchiveReason(JsonNode archive)
        => SyncContentPolicy.ArchiveReason(Text(archive["reason"])!, Text(archive["deletionOrigin"]));

    internal static SyncPreferences Preferences(JsonNode source) => new(
        source["savedStructure"]!.GetValue<bool>(), source["currentTabs"]!.GetValue<bool>(), source["historyAndArchive"]!.GetValue<bool>());

    public static JsonArray Project(JsonObject session, JsonNode preferences, IEnumerable<JsonObject> existingRecords) {
        var policy = Preferences(preferences);
        var existing = new Dictionary<string, string?>(StringComparer.Ordinal);
        var archiveReasons = new Dictionary<Guid, string?>();
        foreach (var record in existingRecords) {
            if (record["payload"]?["value"] is not { } value) continue;
            string kind = record["id"]!["kind"]!.GetValue<string>();
            string name = kind + ":" + Id(record["id"]!["value"]).ToString("D");
            existing[name] = Text(kind == "archive" ? value["tab"]?["orderToken"] : value["orderToken"]);
            if (kind == "archive") archiveReasons[Id(record["id"]!["value"])] = Text(value["reason"]);
        }
        var result = new JsonArray();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        void Add(string kind, JsonObject value) {
            string name = kind + ":" + Id(kind == "archive" ? value["tab"]!["id"] : value["id"]).ToString("D");
            if (!seen.Add(name)) throw new NativeSyncDocumentException("duplicateRecord", name);
            if (seen.Count > NativeSyncJournal.MaximumRecords) throw new NativeSyncDocumentException("recordLimitExceeded", seen.Count.ToString());
            result.Add((JsonNode)new JsonObject { ["type"] = kind, ["value"] = value });
        }
        IReadOnlyList<string> Tokens(string kind, IReadOnlyList<JsonNode> items, bool archived = false)
            => SyncOrderTokens.Allocate(items.Select(item => existing.GetValueOrDefault(kind + ":"
                + Id(archived ? item["tab"]!["id"] : item["id"]).ToString("D"))).ToArray());

        var spaces = Items(session, "spaces").Select(n => n!).ToArray();
        var spaceTokens = Tokens("space", spaces);
        for (int i = 0; i < spaces.Length; i++) {
            var space = spaces[i];
            var portable = Items(space, "tabs").Where(t => PortableTab(t!)).Select(t => t!).ToArray();
            var splitIds = portable.Where(t => t["splitGroupID"] is not null).Select(t => Id(t["splitGroupID"])).ToHashSet();
            var spaceValue = Fields(space, "id", "name", "symbol", "accent", "branding", "browsingPreferences",
                "accessPolicy", "isSavedTabsExpanded", "savedTabsExpansionModifiedAt");
            spaceValue["profileID"] = space["profile"]!["id"]!.DeepClone();
            spaceValue["splitGroups"] = new JsonArray(Items(space, "splitGroups")
                .Where(g => splitIds.Contains(Id(g!["id"]))).Select(g => g!.DeepClone()).ToArray());
            spaceValue["orderToken"] = spaceTokens[i];
            Add("space", spaceValue);

            if (policy.CurrentTabs || policy.SavedStructure) {
                var folders = Items(space, "folders").Where(f => policy.Includes(Placement(f!, "location"))).Select(f => f!).ToArray();
                var tree = new FolderTree(folders.Select(f => new BrowserFolder(new(Id(f["id"])), Text(f["title"])!,
                    Placement(f, "location"), f["parentID"] is { } parent ? new FolderId(Id(parent)) : null)).ToArray());
                IReadOnlyList<BrowserFolder> display;
                try { display = tree.DisplayOrder(); } catch (BrowserRuleException) { throw new NativeSyncDocumentException("invalidFolderHierarchy", Id(space["id"]).ToString("D")); }
                var byId = folders.ToDictionary(f => new FolderId(Id(f["id"])));
                var folderTokens = new Dictionary<FolderId, string>();
                foreach (var parent in new FolderId?[] { null }.Concat(display.Select(f => (FolderId?)f.Id))) {
                    var children = tree.Children(parent).ToArray();
                    var tokens = Tokens("folder", children.Select(f => byId[f.Id]).ToArray());
                    for (int j = 0; j < children.Length; j++) folderTokens[children[j].Id] = tokens[j];
                }
                foreach (var folder in display) {
                    var value = Fields(byId[folder.Id], "id", "title", "location", "symbol", "color", "parentID",
                        "isCollapsed", "collapseModifiedAt", "orderAnchorTabID");
                    value["spaceID"] = space["id"]!.DeepClone();
                    value["orderToken"] = folderTokens[folder.Id];
                    Add("folder", value);
                }
            }

            var tabs = portable.Where(t => policy.Includes(Placement(t))).ToArray();
            var tabTokens = Tokens("tab", tabs);
            for (int j = 0; j < tabs.Length; j++) Add("tab", Tab(tabs[j], space["id"]!, tabTokens[j], archived: false));
            if (!policy.HistoryAndArchive) continue;
            foreach (var history in Items(space, "history").Where(h => SyncContentPolicy.Includes(Text(h!["url"])))) {
                var value = Fields(history!, "id", "url", "title", "firstVisitedAt", "lastVisitedAt", "visitCount");
                value["spaceID"] = space["id"]!.DeepClone();
                Add("history", value);
            }
            // Archive presentation sorts by date after a merge. That is not a
            // user reorder: keep accepted positions and append new identities.
            var archive = Items(space, "archivedTabs").Where(a => PortableTab(a!["tab"]!)).Select(a => a!)
                .OrderBy(a => existing.GetValueOrDefault("archive:" + Id(a["tab"]!["id"]).ToString("D")) ?? "~", StringComparer.Ordinal)
                .ThenBy(a => Id(a["tab"]!["id"]).ToString("D"), StringComparer.Ordinal).ToArray();
            var archiveTokens = Tokens("archive", archive, archived: true);
            for (int j = 0; j < archive.Length; j++) Add("archive", new JsonObject {
                ["tab"] = Tab(archive[j]["tab"]!, space["id"]!, archiveTokens[j], archived: true),
                ["archivedAt"] = archive[j]["archivedAt"]!.DeepClone(),
                ["reason"] = SyncContentPolicy.ProjectArchiveReason(ArchiveReason(archive[j]),
                    archiveReasons.GetValueOrDefault(Id(archive[j]["tab"]!["id"])))
            });
        }
        return result;
    }

    private static JsonObject Tab(JsonNode source, JsonNode spaceId, string token, bool archived) {
        var value = Fields(source, "id", "title", "url", "symbol", "lastActivatedAt", "positionModifiedAt", "customTitle", "titleModifiedAt", "keepsPageLoaded");
        value["spaceID"] = spaceId.DeepClone(); value["orderToken"] = token;
        value["placement"] = archived ? JsonValue.Create("current") : source["placement"]!.DeepClone();
        if (!archived) {
            if (SavedUrl(source) is { } saved) value["savedURL"] = saved;
            foreach (string field in new[] { "folderID", "splitGroupID" })
                if (source[field] is { } content) value[field] = content.DeepClone();
        }
        return value;
    }

    #endregion
}
