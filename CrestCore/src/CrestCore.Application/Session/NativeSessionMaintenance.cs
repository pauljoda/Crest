using System.Text.Json.Nodes;

using CrestCore.Domain;

using static CrestCore.Application.NativeSyncProjection;

namespace CrestCore.Application;

/// Checkpoint repair and retention operate on detached documents. Native image
/// bytes never enter the document; the result identifies which live assets to
/// reattach, even when repair changed a colliding tab or Space identity.
public static class NativeSessionMaintenance {
    #region Actions - Session maintenance

    private static Guid Id(JsonNode? node) {
        if (node is JsonObject wrapped) node = wrapped["rawValue"];
        return Guid.TryParse(node?.GetValue<string>(), out var id) ? id : throw new BrowserRuleException("invalid_saved_identity");
    }

    private static Guid? OptionalId(JsonNode? node) => node is null ? null : Id(node);

    private static JsonObject SwiftId(Guid id) => new() { ["rawValue"] = id.ToString("D") };

    private static JsonArray Array(IEnumerable<JsonNode> nodes) => new(nodes.Select(n => n.DeepClone()).ToArray());

    private static bool StartPage(JsonNode tab) => tab["url"] is null && tab["nativeContent"] is null;

    private static TabPlacement StoredPlacement(JsonNode tab)
        => TabPlacementCodes.Parse(Text(tab["placement"])) ?? TabPlacement.Saved;

    private static BrowserFolder Folder(JsonNode f) => new(new(Id(f["id"])), Text(f["title"])!,
        Text(f["location"]) == TabPlacementCodes.Current ? TabPlacement.Current : TabPlacement.Saved,
        OptionalId(f["parentID"]) is { } p ? new(p) : null);

    private static string? Trim(string? text) => string.IsNullOrWhiteSpace(text) ? null : text.Trim();

    private static void NormalizeDate(JsonObject node, string field) {
        if (node[field] is not { } value) return;
        node[field] = NativeEditTimestamp.Normalize(value.GetValue<double>());
    }

    private static void NormalizeTab(JsonObject tab) {
        tab.Remove("faviconData");
        if (tab["nativeContent"] is not null) { tab.Remove("url"); tab.Remove("savedURL"); }
        tab["customTitle"] = Trim(Text(tab["customTitle"]));
        NormalizeDate(tab, "positionModifiedAt"); NormalizeDate(tab, "titleModifiedAt");
        if (StartPage(tab)) { tab["title"] = "Start Page"; tab["symbol"] = "flag.fill"; }
        tab["keepsPageLoaded"] ??= JsonValue.Create(false);
    }

    private static JsonObject StartTab(double now, IIdSource ids) => new() {
        ["id"] = SwiftId(ids.Next()),
        ["title"] = "Start Page",
        ["symbol"] = "flag.fill",
        ["placement"] = TabPlacementCodes.Current,
        ["lastActivatedAt"] = now,
        ["keepsPageLoaded"] = false
    };

    public static JsonObject Repair(JsonObject source, double now, JsonObject? emptySpace = null, IIdSource? ids = null) {
        if (!double.IsFinite(now)) throw new BrowserRuleException("invalid_saved_date");
        ids ??= new SystemIdSource();
        var result = source.DeepClone().AsObject();
        var spaces = Items(result, "spaces");
        var pending = (source["spaceDeletions"] as JsonArray ?? new()).Select(n => Id(n!["spaceID"])).ToHashSet();
        var pendingSpaces = spaces.Where(s => pending.Contains(Id(s!["id"]))).ToDictionary(s => Id(s!["id"]), s => s!.DeepClone());
        if (spaces.Count == 0 || spaces.All(s => pending.Contains(Id(s!["id"])))) {
            var blank = emptySpace?.DeepClone().AsObject() ?? new JsonObject { ["name"] = "Space 1", ["symbol"] = "square.grid.2x2.fill", ["accent"] = SpaceAccentCodes.Indigo };
            blank["id"] = SwiftId(ids.Next()); blank["profile"] = new JsonObject { ["id"] = ids.Next().ToString("D") };
            var tab = StartTab(now, ids);
            blank["selectedTabID"] = tab["id"]!.DeepClone();
            blank["tabs"] = new JsonArray(tab); blank["folders"] = new JsonArray();
            blank["archivedTabs"] = new JsonArray(); blank["history"] = new JsonArray();
            if (spaces.Count == 0) { spaces = new JsonArray(blank); result["spaces"] = spaces; } else spaces.Add((JsonNode)blank);
            result["selectedSpaceID"] = blank["id"]!.DeepClone();
        }
        var spaceIds = new RuntimeIdentityRegistry(ids); var profiles = new RuntimeIdentityRegistry(ids);
        var tabIds = new RuntimeIdentityRegistry(ids); var assets = new JsonArray();
        for (int si = 0; si < spaces.Count; si++) {
            var space = spaces[si]!.AsObject(); var oldSpaceId = Id(space["id"]);
            space["id"] = SwiftId(spaceIds.Claim(oldSpaceId));
            space["profile"]!["id"] = profiles.Claim(Id(space["profile"]!["id"])).ToString("D");
            var folderIds = new RuntimeIdentityRegistry(ids);
            var uniqueFolders = Items(space, "folders").Select(f => {
                var folder = f!.DeepClone().AsObject(); folder["id"] = SwiftId(folderIds.Claim(Id(folder["id"]))); return folder;
            }).ToArray();
            var folderMetadata = uniqueFolders.ToDictionary(f => Id(f["id"]));
            var folders = FolderTree.RepairPreorder(uniqueFolders.Select(Folder).ToArray());
            space["folders"] = new JsonArray(folders.Select(f => {
                var value = folderMetadata[f.Id.Value]; value["parentID"] = f.ParentId is { } p ? SwiftId(p.Value) : null;
                value["location"] = f.Location == TabPlacement.Current ? TabPlacementCodes.Current : TabPlacementCodes.Saved;
                return (JsonNode)value;
            }).ToArray());
            var folderLocations = folders.ToDictionary(f => f.Id.Value, f => f.Location);
            var tabs = Items(space, "tabs"); Guid? selected = null;
            var previousSelection = OptionalId(space["selectedTabID"]); int pinned = 0;
            for (int ti = 0; ti < tabs.Count; ti++) {
                var tab = tabs[ti]!.AsObject(); var oldId = Id(tab["id"]);
                var id = tabIds.Claim(oldId); tab["id"] = SwiftId(id);
                assets.Add((JsonNode)new JsonObject {
                    ["spaceIndex"] = si,
                    ["tabIndex"] = ti,
                    ["sourceSpaceID"] = SwiftId(oldSpaceId),
                    ["sourceTabID"] = SwiftId(oldId)
                });
                var placement = StoredPlacement(tab);
                if (placement == TabPlacement.Pinned && ++pinned > 12) placement = TabPlacement.Saved;
                tab["placement"] = TabPlacementCodes.Name(placement);
                if (placement == TabPlacement.Current) tab.Remove("savedURL");
                else tab["savedURL"] ??= tab["url"]?.DeepClone();
                if (placement == TabPlacement.Pinned || OptionalId(tab["folderID"]) is not { } folder
                    || !folderLocations.TryGetValue(folder, out var location) || location != placement) tab.Remove("folderID");
                NormalizeTab(tab);
                if (selected is null && previousSelection == oldId) selected = id;
            }
            if (tabs.Count == 0) {
                var tab = StartTab(now, ids); tab["id"] = SwiftId(tabIds.Claim(Id(tab["id"])));
                tabs.Add((JsonNode)tab); selected = Id(tab["id"]);
                if (space["tabs"] is null) space["tabs"] = tabs;
            }
            var groups = SplitMembershipPolicy.Repair(tabs.Select(t => new SplitMember(OptionalId(t!["splitGroupID"]), StoredPlacement(t),
                OptionalId(t["folderID"]) is { } f ? new FolderId(f) : null)).ToArray());
            for (int ti = 0; ti < tabs.Count; ti++) tabs[ti]!["splitGroupID"] = groups[ti] is { } group ? SwiftId(group) : null;
            var archive = Items(space, "archivedTabs").Where(a => !StartPage(a!["tab"]!)).Select(a => {
                var value = a!.DeepClone().AsObject(); var tab = value["tab"]!.AsObject();
                tab["id"] = SwiftId(tabIds.Claim(Id(tab["id"]))); tab["placement"] = TabPlacementCodes.Current;
                tab.Remove("savedURL"); tab.Remove("folderID"); tab.Remove("splitGroupID"); NormalizeTab(tab);
                return (JsonNode)value;
            });
            space["archivedTabs"] = new JsonArray(archive.ToArray());
            space["history"] = Array(Items(space, "history").Take(HistoryPolicy.MaximumEntries).Select(n => n!));
            space["splitGroups"] = NormalizeGroups(Items(space, "splitGroups"));
            var fallback = tabs.FirstOrDefault(t => StoredPlacement(t!) == TabPlacement.Current)
                ?? tabs.FirstOrDefault(t => StoredPlacement(t!) == TabPlacement.Pinned) ?? tabs[0];
            space["selectedTabID"] = selected is { } chosen ? SwiftId(chosen) : fallback!["id"]!.DeepClone();
        }
        for (int index = 0; index < spaces.Count; index++)
            if (pendingSpaces.TryGetValue(Id(spaces[index]!["id"]), out var original)) {
                if (Id(spaces[index]!["profile"]!["id"]) != Id(original["profile"]!["id"]))
                    throw new BrowserRuleException("invalid_deletion_intent");
                spaces[index] = original.DeepClone();
            }
        var activeIds = spaces.Select(s => Id(s!["id"])).ToHashSet();
        if (OptionalId(result["selectedSpaceID"]) is not { } active || !activeIds.Contains(active) || pending.Contains(active))
            result["selectedSpaceID"] = spaces.First(s => !pending.Contains(Id(s!["id"])))!["id"]!.DeepClone();
        if (OptionalId(result["defaultSpaceID"]) is not { } launch || !activeIds.Contains(launch)) result["defaultSpaceID"] = result["selectedSpaceID"]!.DeepClone();
        return new() { ["session"] = result, ["assets"] = assets };
    }

    private static JsonArray NormalizeGroups(JsonArray source) {
        Dictionary<Guid, JsonObject> groups = [];
        foreach (var node in source) {
            var group = node!.DeepClone().AsObject(); var id = Id(group["id"]);
            group["customTitle"] = Trim(Text(group["customTitle"]));
            // The native presentation codec normalizes glyphs for its Unicode
            // vocabulary. Keep the chosen icon opaque while merging its clock.
            foreach (string field in new[] { "titleModifiedAt", "iconModifiedAt", "tintModifiedAt" }) NormalizeDate(group, field);
            if (groups.TryGetValue(id, out var previous))
                foreach (var (clock, value) in new[] { ("titleModifiedAt", "customTitle"), ("iconModifiedAt", "customIconSymbol"), ("tintModifiedAt", "tint") })
                    if (SyncConflictPolicy.Latest(group[clock]?.GetValue<double>(), previous[clock]?.GetValue<double>()) == 1) { group[clock] = previous[clock]?.DeepClone(); group[value] = previous[value]?.DeepClone(); }
            groups[id] = group;
        }
        return new(groups.Values.Select(g => (JsonNode)g).ToArray());
    }

    public static JsonObject Retain(JsonObject source, double now) {
        if (!double.IsFinite(now)) throw new BrowserRuleException("invalid_saved_date");
        var session = source.DeepClone().AsObject(); bool changed = false;
        var pending = (source["spaceDeletions"] as JsonArray ?? new()).Select(n => Id(n!["spaceID"])).ToHashSet();
        foreach (var space in Items(session, "spaces").Where(s => !pending.Contains(Id(s!["id"]))))
            foreach (var (section, preference, date) in new[] { ("history", "history", "lastVisitedAt"), ("archivedTabs", "archive", "archivedAt") }) {
                var term = Text(space!["browsingPreferences"]?["dataRetention"]?[preference]);
                var duration = Enum.TryParse<DataRetention>(term, true, out var parsed) && Enum.IsDefined(parsed) ? parsed : DataRetention.Forever;
                if (RetentionPreferences.Lifetime(duration) is not { } lifetime) continue;
                var records = Items(space, section);
                var expired = RecordRemovalPolicy.Expired(records.Select(r => r![date]!.GetValue<double>()).ToArray(), now, lifetime.TotalSeconds);
                foreach (int index in expired.Reverse()) records.RemoveAt(index);
                changed |= expired.Count != 0;
            }
        return new() { ["session"] = session, ["changed"] = changed };
    }

    #endregion
}
