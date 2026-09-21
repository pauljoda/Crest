using System.Text.Json.Nodes;

using CrestCore.Domain;

using static CrestCore.Application.NativeSyncProjection;

namespace CrestCore.Application;

/// Converts shared records into the native session document. Device credentials
/// and engine-local pages come only from the receiving device's checkpoint.
public static class NativeSyncMaterializer {
    #region Actions - Materialization

    private static Guid? OptionalId(JsonNode? node) => node is null ? null : Id(node);

    private static JsonObject SwiftId(Guid id) => new() { ["rawValue"] = id.ToString("D") };

    private static JsonArray Array(IEnumerable<JsonNode> items) => new(items.Select(n => n.DeepClone()).ToArray());

    private static IEnumerable<JsonNode> Local(JsonNode? space, string section) => space is null ? [] : Items(space, section).Select(n => n!);

    private static IEnumerable<JsonNode> Ordered(IEnumerable<JsonNode> source) => source
        .OrderBy(n => Text(n["orderToken"]), StringComparer.Ordinal).ThenBy(n => Id(n["id"]).ToString("D"), StringComparer.Ordinal);

    private static IEnumerable<JsonNode> Payloads(IEnumerable<JsonObject> records, string kind, Guid? space = null)
        => records.Where(r => Text(r["payload"]?["type"]) == kind && (space is null || Id(r["spaceID"]) == space))
            .Select(r => r["payload"]!["value"]!);

    private static BrowserFolder Folder(JsonNode node) => new(new(Id(node["id"])), Text(node["title"])!, Placement(node, "location"),
        OptionalId(node["parentID"]) is { } parent ? new(parent) : null);

    private static Dictionary<FolderId, BrowserFolder> LocalFolders(JsonNode? space)
        => Local(space, "folders").Select(Folder).ToDictionary(f => f.Id);

    private static NativeSyncDocumentException Error(string code, Guid id) => new(code, id.ToString("D"));

    public static JsonObject Materialize(JsonObject session, JsonNode preferences, IReadOnlyList<JsonObject> records, double now) {
        var policy = Preferences(preferences);
        var owners = records.Where(r => Text(r["id"]?["kind"]) == SyncRecordKinds.Folder)
            .ToDictionary(r => new FolderId(Id(r["id"]!["value"])), r => new SpaceId(Id(r["spaceID"])));
        var deleted = records.Where(r => Text(r["id"]?["kind"]) == SyncRecordKinds.Folder && r["tombstone"] is not null)
            .Select(r => new FolderId(Id(r["id"]!["value"]))).ToHashSet();
        var localSpaces = Items(session, "spaces").ToDictionary(n => Id(n!["id"]), n => n!);
        var pending = (session["spaceDeletions"] as JsonArray ?? new()).Select(n => Id(n!["spaceID"])).ToHashSet();
        var spaces = new JsonArray();
        HashSet<Guid> profiles = [];
        foreach (var remote in Ordered(Payloads(records, SyncRecordKinds.Space))) {
            var id = Id(remote["id"]); var profile = Id(remote["profileID"]);
            if (!profiles.Add(profile)) throw Error(NativeSyncDocumentErrorCodes.DuplicateProfile, profile);
            localSpaces.TryGetValue(id, out var local);
            if (local is not null && Id(local["profile"]!["id"]) != profile) throw Error(NativeSyncDocumentErrorCodes.ImmutableProfileChanged, id);
            if (pending.Contains(id) && local is not null) { spaces.Add(local.DeepClone()); continue; }
            var folders = Folders(id, records, policy, local, owners, deleted);
            var tabs = Tabs(id, records, policy, local, folders, owners, deleted);
            var archive = Archive(id, records, policy, local, tabs, now);
            var history = History(id, records, policy, local);
            var localSplitIds = Local(local, "tabs").Where(t => !PortableTab(t) && t["splitGroupID"] is not null)
                .Select(t => Id(t["splitGroupID"])).ToHashSet();
            var groups = (remote["splitGroups"] is JsonArray supplied ? supplied.Select(n => n!) : Local(local, "splitGroups")).ToList();
            var groupIds = groups.Select(g => Id(g["id"])).ToHashSet();
            groups.AddRange(Local(local, "splitGroups").Where(g => localSplitIds.Contains(Id(g["id"])) && !groupIds.Contains(Id(g["id"]))));
            if (tabs.Count == 0) tabs.Add(new JsonObject {
                ["id"] = SwiftId(Guid.NewGuid()),
                ["title"] = "Start Page",
                ["symbol"] = "flag.fill",
                ["placement"] = TabPlacementCodes.Current,
                ["lastActivatedAt"] = now
            });
            var value = Fields(remote, "id", "name", "symbol", "accent", "branding", "browsingPreferences", "accessPolicy",
                "isSavedTabsExpanded", "savedTabsExpansionModifiedAt");
            value["profile"] = new JsonObject { ["id"] = remote["profileID"]!.DeepClone() };
            value["folders"] = Array(folders); value["tabs"] = Array(tabs); value["splitGroups"] = Array(groups);
            value["archivedTabs"] = Array(archive); value["history"] = Array(history);
            if (local?["credentialPreferences"] is { } credentials) value["credentialPreferences"] = credentials.DeepClone();
            if (local?["selectedTabID"] is { } selected && tabs.Any(t => Id(t["id"]) == Id(selected)))
                value["selectedTabID"] = selected.DeepClone();
            spaces.Add((JsonNode)value);
        }
        foreach (var id in pending.Where(id => !spaces.Any(s => Id(s!["id"]) == id))) {
            var local = localSpaces[id];
            if (!profiles.Add(Id(local["profile"]!["id"]))) throw Error(NativeSyncDocumentErrorCodes.DuplicateProfile, Id(local["profile"]!["id"]));
            spaces.Add(local.DeepClone());
        }
        var result = session.DeepClone().AsObject();
        if (spaces.Count == 0) return result;
        result.Remove("disposableSeedMarker");
        result["spaces"] = spaces;
        if (!spaces.Any(s => Id(s!["id"]) == Id(session["selectedSpaceID"])))
            result["selectedSpaceID"] = spaces[0]!["id"]!.DeepClone();
        return result;
    }

    private static List<JsonNode> Folders(Guid space, IReadOnlyList<JsonObject> records, SyncPreferences policy, JsonNode? local,
        IReadOnlyDictionary<FolderId, SpaceId> owners, HashSet<FolderId> deleted) {
        var synced = Ordered(Payloads(records, SyncRecordKinds.Folder, space).Where(f => policy.Includes(Placement(f, "location")))).ToArray();
        IReadOnlyList<BrowserFolder> resolved;
        try { resolved = SyncFolderMaterialization.Resolve(new(space), synced.Select(Folder).ToArray(), owners, LocalFolders(local), deleted); } catch (BrowserRuleException) { throw Error(NativeSyncDocumentErrorCodes.InvalidFolderHierarchy, space); }
        var byId = synced.ToDictionary(f => Id(f["id"]));
        var result = resolved.Select(folder => {
            var value = Fields(byId[folder.Id.Value], "id", "title", "location", "symbol", "color", "isCollapsed", "collapseModifiedAt", "orderAnchorTabID");
            if (folder.ParentId is { } parent) value["parentID"] = SwiftId(parent.Value);
            return (JsonNode)value;
        }).ToList();
        var included = resolved.Select(f => f.Id.Value).ToHashSet();
        result.AddRange(Local(local, "folders").Where(f => !included.Contains(Id(f["id"])) && !policy.Includes(Placement(f, "location"))));
        return result;
    }

    private static JsonObject Tab(JsonNode remote, JsonNode? local, bool archived = false) {
        var value = Fields(remote, "id", "title", "url", "nativeContent", "symbol", "lastActivatedAt", "positionModifiedAt",
            "customTitle", "titleModifiedAt", "keepsPageLoaded");
        value["placement"] = archived ? JsonValue.Create(TabPlacementCodes.Current) : remote["placement"]!.DeepClone();
        if (!archived) {
            if (Placement(remote) != TabPlacement.Current && SavedUrl(remote) is { } saved) value["savedURL"] = saved;
            value["splitGroupID"] = remote["splitGroupID"]?.DeepClone();
        }
        if (local is not null)
            foreach (string field in new[] { "faviconURL", "iconAccent", "storedIconMode" })
                if (local[field] is { } asset) value[field] = asset.DeepClone();
        return value;
    }

    private static List<JsonNode> Tabs(Guid space, IReadOnlyList<JsonObject> records, SyncPreferences policy, JsonNode? local,
        IReadOnlyList<JsonNode> folders, IReadOnlyDictionary<FolderId, SpaceId> owners, HashSet<FolderId> deleted) {
        var locals = Local(local, "tabs").ToArray();
        var localOnly = locals.Select((tab, index) => (tab, index)).Where(t => !PortableTab(t.tab)).ToArray();
        var localOnlyIds = localOnly.Select(t => Id(t.tab["id"]))
            .Concat(Local(local, "archivedTabs").Where(a => !PortableTab(a["tab"]!)).Select(a => Id(a["tab"]!["id"]))).ToHashSet();
        var synced = Ordered(Payloads(records, SyncRecordKinds.Tab, space)
                .Where(t => PortableTab(t) && !localOnlyIds.Contains(Id(t["id"])) && policy.Includes(Placement(t))))
            .OrderBy(t => Placement(t) switch { TabPlacement.Pinned => 0, TabPlacement.Saved => 1, _ => 2 }).ToArray();
        var syncedIds = synced.Select(t => Id(t["id"])).ToHashSet();
        var result = locals.Where(t => PortableTab(t) && !policy.Includes(Placement(t)) && !syncedIds.Contains(Id(t["id"]))).ToList();
        var byId = locals.ToDictionary(t => Id(t["id"]));
        var folderIds = folders.Select(f => new FolderId(Id(f["id"]))).ToHashSet();
        var localFolders = LocalFolders(local);
        foreach (var tab in synced) {
            FolderId? folder = OptionalId(tab["folderID"]) is { } fid ? new(fid) : null;
            if (Placement(tab) != TabPlacement.Pinned && folder is { } missing && !folderIds.Contains(missing)) {
                if (owners.TryGetValue(missing, out var owner) && owner.Value != space) throw Error(NativeSyncDocumentErrorCodes.DanglingFolder, Id(tab["id"]));
                if (!SyncFolderMaterialization.TryPromote(missing, folderIds, localFolders, deleted, out folder)) continue;
            }
            var value = Tab(tab, byId.GetValueOrDefault(Id(tab["id"])));
            if (Placement(tab) != TabPlacement.Pinned && folder is { } resolved) value["folderID"] = SwiftId(resolved.Value);
            result.Add(value);
        }
        if (result.Count(t => Placement(t) == TabPlacement.Pinned) > 12) throw Error(NativeSyncDocumentErrorCodes.TooManyPinnedTabs, space);
        foreach (var (tab, index) in localOnly) result.Insert(Math.Min(index, result.Count), tab);
        return result;
    }

    private static List<JsonNode> Archive(Guid space, IReadOnlyList<JsonObject> records, SyncPreferences policy, JsonNode? local,
        IReadOnlyList<JsonNode> tabs, double now) {
        if (!policy.HistoryAndArchive) return Local(local, "archivedTabs").ToList();
        var active = tabs.Select(t => Id(t["id"])).ToHashSet();
        var byId = Local(local, "archivedTabs").ToDictionary(a => Id(a["tab"]!["id"]));
        var localOnly = byId.Values.Where(a => !PortableTab(a["tab"]!) && !active.Contains(Id(a["tab"]!["id"]))).ToArray();
        var localOnlyIds = localOnly.Select(a => Id(a["tab"]!["id"])).ToHashSet();
        var remote = Payloads(records, SyncRecordKinds.Archive, space).Where(a => PortableTab(a["tab"]!)
            && !localOnlyIds.Contains(Id(a["tab"]!["id"])) && !active.Contains(Id(a["tab"]!["id"])))
            .OrderBy(a => Text(a["tab"]!["orderToken"]), StringComparer.Ordinal)
            .ThenBy(a => Id(a["tab"]!["id"]).ToString("D"), StringComparer.Ordinal);
        List<JsonNode> result = [];
        foreach (var archive in remote) {
            byId.TryGetValue(Id(archive["tab"]!["id"]), out var previous);
            var value = new JsonObject {
                ["tab"] = Tab(archive["tab"]!, previous?["tab"], archived: true),
                ["archivedAt"] = archive["archivedAt"]!.DeepClone()
            };
            if (previous is not null) {
                value["reason"] = previous["reason"]!.DeepClone(); value["deletionOrigin"] = previous["deletionOrigin"]?.DeepClone();
            } else {
                value["reason"] = ArchiveReasons.Synced;
                if (Text(archive["reason"]) is ArchiveReasons.Deleted or ArchiveReasons.DeletedOnAnotherDevice)
                    value["deletionOrigin"] = SyncDeletionOrigins.Remote;
            }
            result.Add(value);
        }
        var projected = result.Select(a => Id(a["tab"]!["id"])).ToHashSet();
        var localTabs = Local(local, "tabs").Where(PortableTab).ToDictionary(t => Id(t["id"]));
        foreach (var record in records.Where(r => Text(r["id"]?["kind"]) == SyncRecordKinds.Tab && Id(r["spaceID"]) == space
            && Text(r["tombstone"]?["reason"]) == SyncDeletionReasons.ExplicitDelete)) {
            var id = Id(record["id"]!["value"]);
            if (projected.Contains(id) || !localTabs.TryGetValue(id, out var tab)) continue;
            result.Add(new JsonObject {
                ["tab"] = Tab(tab, tab, archived: true),
                ["reason"] = ArchiveReasons.Synced,
                ["deletionOrigin"] = SyncDeletionOrigins.Remote,
                ["archivedAt"] = record["tombstone"]?["deletedAt"]?.DeepClone() ?? JsonValue.Create(now)
            });
        }
        return result.Concat(localOnly).OrderByDescending(a => a["archivedAt"]!.GetValue<double>()).ToList();
    }

    private static List<JsonNode> History(Guid space, IReadOnlyList<JsonObject> records, SyncPreferences policy, JsonNode? local) {
        if (!policy.HistoryAndArchive) return Local(local, "history").ToList();
        var localOnly = Local(local, "history").Where(h => !SyncContentPolicy.Includes(Text(h["url"]))).ToArray();
        var localIds = localOnly.Select(h => Id(h["id"])).ToHashSet();
        var synced = Payloads(records, SyncRecordKinds.History, space).Where(h => SyncContentPolicy.Includes(Text(h["url"])) && !localIds.Contains(Id(h["id"])))
            .OrderByDescending(h => h["lastVisitedAt"]!.GetValue<double>()).ThenBy(h => Id(h["id"]).ToString("D"), StringComparer.Ordinal)
            .Take(HistoryPolicy.MaximumEntries).Select(h => (JsonNode)Fields(h, "id", "url", "title", "firstVisitedAt", "lastVisitedAt", "visitCount"));
        return synced.Concat(localOnly).OrderByDescending(h => h["lastVisitedAt"]!.GetValue<double>()).ToList();
    }

    #endregion
}
