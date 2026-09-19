using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Reads Crest's existing Swift Codable session. Unowned/additive fields survive
/// round trips verbatim as JSON values; only fields owned by the domain are replaced.
public sealed class LegacySessionDocument
{
    private static readonly DateTimeOffset SwiftEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private readonly JsonObject original;
    private readonly Dictionary<Guid, JsonObject> spaces = [];
    private readonly Dictionary<Guid, JsonObject> tabs = [];
    private readonly Dictionary<Guid, JsonObject> folders = [];
    private readonly Dictionary<Guid, JsonObject> archives = [];
    private readonly Dictionary<Guid, JsonObject> histories = [];
    private readonly Dictionary<Guid, JsonObject> windows = [];
    private readonly Dictionary<Guid, SearchPreferences> searchPreferences = [];
    private readonly Dictionary<Guid, RetentionPreferences> retentionPreferences = [];
    private readonly Dictionary<Guid, ContentBlockingPolicy> contentBlockingPolicies = [];

    public LegacySessionDocument(JsonObject? source = null) => original = (JsonObject?)source?.DeepClone() ?? new();
    public void CopyTabMetadata(TabId source, TabId destination)
    {
        if (tabs.TryGetValue(source.Value, out var value)) tabs[destination.Value] = (JsonObject)value.DeepClone();
    }
    internal void TransferTabMetadata(TabId tab, LegacySessionDocument destination)
    {
        if (tabs.TryGetValue(tab.Value, out var value)) destination.tabs[tab.Value] = (JsonObject)value.DeepClone();
    }
    private static JsonObject Object(JsonNode? node) => node as JsonObject ?? throw new BrowserRuleException("invalid_saved_state");
    private static JsonArray Array(JsonNode? node) => node is null ? [] : node as JsonArray ?? throw new BrowserRuleException("invalid_saved_state");
    private static string? Text(JsonNode? node) => node is null ? null : node.GetValue<string>();
    private static Guid Id(JsonNode? node)
    {
        if (node is JsonObject o) node = o["rawValue"];
        if (!Guid.TryParseExact(Text(node), "D", out var id) || id == Guid.Empty) throw new BrowserRuleException("invalid_saved_identity");
        return id;
    }
    private static Guid? OptionalId(JsonNode? node) => node is null ? null : Id(node);
    private static DateTimeOffset Date(JsonNode? node)
    {
        var seconds = node?.GetValue<double>() ?? 0;
        if (!double.IsFinite(seconds)) throw new BrowserRuleException("invalid_saved_date");
        return SwiftEpoch.AddSeconds(seconds);
    }
    private static DateTimeOffset? OptionalDate(JsonNode? node) => node is null ? null : Date(node);
    private static JsonObject SwiftId(Guid id) => new() { ["rawValue"] = id.ToString().ToUpperInvariant() };
    private static JsonNode? SwiftId(Guid? id) => id is { } value ? SwiftId(value) : null;
    private static double Seconds(DateTimeOffset date) => (date - SwiftEpoch).TotalSeconds;
    private static void WriteDate(JsonObject value, string key, DateTimeOffset? date)
    {
        // Swift Date stores a Double, with precision that differs from .NET ticks.
        // Preserve its original number when the domain has not changed this field.
        if (date is { } d && value[key] is { } originalDate && Date(originalDate) == d) return;
        value[key] = date is { } updated ? Seconds(updated) : null;
    }
    private static JsonObject Copy(Dictionary<Guid, JsonObject> originals, Guid id)
        => originals.TryGetValue(id, out var value) ? (JsonObject)value.DeepClone() : new();
    private static void Remember(Dictionary<Guid, JsonObject> values, Guid id, JsonObject value)
    {
        if (!values.TryAdd(id, value)) throw new BrowserRuleException("duplicate_persisted_identity");
    }
    private static TabPlacement Placement(JsonNode? node) => Text(node) switch
    {
        "current" => TabPlacement.Current, "pinned" => TabPlacement.Pinned, _ => TabPlacement.Saved
    };
    private TabState ReadTab(JsonObject t)
    {
        var id = Id(t["id"]); Remember(tabs, id, t);
        var nativeKind = t["nativeContent"] is JsonObject native ? Text(native["kind"]) : null;
        var url = nativeKind is null ? Text(t["url"]) : null;
        var kind = nativeKind == "settings" ? TabKind.Settings : nativeKind is not null ? TabKind.Native : url is null ? TabKind.StartPage : TabKind.Web;
        var folder = OptionalId(t["folderID"]);
        return new(new(id), kind, url, Text(t["title"]) ?? "Start Page", Placement(t["placement"]),
            folder is { } f ? new FolderId(f) : null, Text(t["savedURL"]), Text(t["customTitle"]),
            Date(t["lastActivatedAt"]), OptionalDate(t["positionModifiedAt"]), OptionalDate(t["titleModifiedAt"]),
            t["keepsPageLoaded"]?.GetValue<bool>() ?? false, OptionalId(t["splitGroupID"]), nativeKind);
    }
    internal TabState ReadNewTab(JsonObject value) => ReadTab(value);
    public WorkspaceState Read(IIdSource ids)
    {
        spaces.Clear(); tabs.Clear(); folders.Clear(); archives.Clear(); histories.Clear(); windows.Clear(); searchPreferences.Clear(); retentionPreferences.Clear();
        var session = Object(original["session"]);
        var states = new List<SpaceState>();
        foreach (var value in Array(session["spaces"]))
        {
            var s = Object(value); var id = Id(s["id"]); Remember(spaces, id, s);
            var folderStates = new List<FolderState>();
            foreach (var fv in Array(s["folders"]))
            {
                var f = Object(fv); var fid = Id(f["id"]); Remember(folders, fid, f);
                var parent = OptionalId(f["parentID"]);
                folderStates.Add(new(new(fid), Text(f["title"]) ?? "Folder", Text(f["location"]) == "current" ? TabPlacement.Current : TabPlacement.Saved,
                    parent is { } p ? new FolderId(p) : null, f["isCollapsed"]?.GetValue<bool>() ?? false,
                    OptionalDate(f["collapseModifiedAt"]), OptionalId(f["orderAnchorTabID"]) is { } anchor ? new TabId(anchor) : null));
            }
            var archived = new List<ArchiveState>();
            foreach (var av in Array(s["archivedTabs"]))
            {
                var a = Object(av); var tab = ReadTab(Object(a["tab"])); Remember(archives, tab.Id.Value, a);
                archived.Add(new(tab, Date(a["archivedAt"]), Text(a["reason"]) ?? "closed"));
            }
            var visits = new List<HistoryVisit>();
            foreach (var hv in Array(s["history"]))
            {
                var h = Object(hv); var hid = Id(h["id"]); Remember(histories, hid, h);
                visits.Add(new(hid, Text(h["url"]) ?? throw new BrowserRuleException("invalid_saved_url"), Text(h["title"]) ?? "",
                    Date(h["firstVisitedAt"]), Date(h["lastVisitedAt"]), h["visitCount"]?.GetValue<int>() ?? 1));
            }
            var selected = OptionalId(s["selectedTabID"]);
            var preferences = s["browsingPreferences"] as JsonObject;
            var customProviders = new List<SearchProvider>();
            foreach (var item in Array(preferences?["customSearchProviders"]))
            {
                try
                {
                    var custom = Object(item);
                    customProviders.Add(SearchProvider.Custom(Id(custom["id"]), Text(custom["name"]) ?? "",
                        Text(custom["searchURLTemplate"]) ?? "", Text(custom["suggestionURLTemplate"])));
                }
                catch (BrowserRuleException) { /* Invalid legacy custom providers are excluded just as in Swift. */ }
            }
            var search = SearchPreferences.Restore(Text(preferences?["selectedSearchProviderID"]) ?? Text(preferences?["searchProvider"]),
                customProviders, preferences?["searchSuggestionsEnabled"]?.GetValue<bool>() ?? false);
            searchPreferences.Add(id, search);
            var retention = new RetentionPreferences(
                ReadEnum(preferences?["currentTabCleanupPolicy"], CurrentTabCleanup.After12Hours, CurrentTabCleanup.Never),
                ReadEnum(preferences?["dataRetention"]?["history"], DataRetention.Forever, DataRetention.Forever),
                ReadEnum(preferences?["dataRetention"]?["archive"], DataRetention.Forever, DataRetention.Forever),
                ReadEnum(preferences?["dataRetention"]?["downloads"], DataRetention.Forever, DataRetention.Forever));
            retentionPreferences.Add(id, retention);
            contentBlockingPolicies.Add(id, ReadEnum(preferences?["contentBlockingPolicy"], ContentBlockingPolicy.Balanced, ContentBlockingPolicy.Balanced));
            states.Add(new(new(id), new(Id(Object(s["profile"])["id"])), Text(s["name"]) ?? "Space",
                Text(s["accessPolicy"]) is { } policy && policy != "open",
                Array(s["tabs"]).Select(t => ReadTab(Object(t))).ToArray(), folderStates, archived, visits,
                selected is { } tabId ? new TabId(tabId) : null, search,
                Text(s["accessPolicy"]) is null or "open" or "deviceOwnerAuthentication", retention,
                ReadEnum(preferences?["contentBlockingPolicy"], ContentBlockingPolicy.Balanced, ContentBlockingPolicy.Balanced)));
        }
        var windowStates = new List<WindowState>();
        foreach (var value in Array(original["windows"]))
        {
            var w = Object(value); var id = Id(w["id"]); Remember(windows, id, w);
            var selections = new Dictionary<SpaceId, TabId?>();
            // Codable dictionaries with struct keys use an alternating key/value array.
            var pairs = Array(w["selectedTabIDsBySpace"]);
            if (pairs.Count % 2 != 0) throw new BrowserRuleException("invalid_saved_selection");
            for (int index = 0; index < pairs.Count; index += 2)
                selections.Add(new(Id(pairs[index])), new TabId(Id(pairs[index + 1])));
            if (w["capturedSpaceIDs"] is not null)
                foreach (var captured in Array(w["capturedSpaceIDs"])) selections.TryAdd(new(Id(captured)), null);
            else
                foreach (var space in states) selections.TryAdd(space.Id, space.SelectedTabId);
            windowStates.Add(new(new(id), new(Id(w["selectedSpaceID"])), selections, Text(w["platformSceneId"])));
        }
        var defaultId = OptionalId(session["defaultSpaceID"]);
        var selectedId = OptionalId(session["selectedSpaceID"]);
        var deletions = Array(original["spaceDeletions"]).Select(value =>
        {
            var deletion = Object(value);
            return new SpaceDeletionState(new(Id(deletion["spaceId"])), new(Id(deletion["profileId"])),
                Date(deletion["requestedAt"]), deletion["completed"]?.GetValue<bool>() ?? false);
        }).ToArray();
        return new(new(OptionalId(original["workspaceId"]) ?? ids.Next()), defaultId is { } d ? new SpaceId(d) : null,
            selectedId is { } selectedSpace ? new SpaceId(selectedSpace) : null, states, windowStates, deletions);
    }
    private static T ReadEnum<T>(JsonNode? value, T missing, T unknown) where T : struct, Enum
        => value is null ? missing : Enum.TryParse<T>(Text(value), true, out var result) && Enum.IsDefined(result) ? result : unknown;
    internal static string EnumName<T>(T value) where T : struct, Enum
    { var text = value.ToString(); return char.ToLowerInvariant(text[0]) + text[1..]; }
    private JsonObject WriteTab(TabState t)
    {
        var value = Copy(tabs, t.Id.Value);
        value["id"] = SwiftId(t.Id.Value); value["title"] = t.Title; value["url"] = t.Url;
        value["placement"] = t.Placement.ToString().ToLowerInvariant(); value["folderID"] = SwiftId(t.FolderId?.Value);
        value["savedURL"] = t.SavedUrl; value["customTitle"] = t.CustomTitle;
        WriteDate(value, "lastActivatedAt", t.LastActivatedAt);
        WriteDate(value, "positionModifiedAt", t.PositionModifiedAt);
        WriteDate(value, "titleModifiedAt", t.TitleModifiedAt);
        value["keepsPageLoaded"] = t.KeepsPageLoaded; value["splitGroupID"] = SwiftId(t.SplitGroupId);
        value["symbol"] ??= t.Kind == TabKind.StartPage ? "flag.fill" : t.Kind == TabKind.Settings ? "gearshape" : "globe";
        if (t.NativeKind is { } nativeKind)
        {
            var native = value["nativeContent"] as JsonObject ?? new(); native["kind"] = nativeKind;
            if (native.Parent is null) value["nativeContent"] = native;
        }
        else value.Remove("nativeContent");
        return value;
    }
    public JsonObject Write(WorkspaceState state)
    {
        var document = (JsonObject)original.DeepClone();
        var session = document["session"] as JsonObject ?? new();
        if (session.Parent is null) document["session"] = session;
        document["workspaceId"] = state.Id.Value.ToString(); document["formatVersion"] = 1;
        document["spaceDeletions"] = new JsonArray((state.SpaceDeletions ?? []).Select(d => (JsonNode)new JsonObject
        {
            ["spaceId"] = d.Space.Value.ToString(), ["profileId"] = d.Profile.Value.ToString(),
            ["requestedAt"] = Seconds(d.RequestedAt), ["completed"] = d.Completed
        }).ToArray());
        session["selectedSpaceID"] = SwiftId(state.SelectedSpaceId?.Value);
        session["defaultSpaceID"] = SwiftId(state.DefaultSpaceId?.Value);
        var spaceValues = new JsonArray(); session["spaces"] = spaceValues;
        foreach (var space in state.Spaces)
        {
            var s = Copy(spaces, space.Id.Value); spaceValues.Add((JsonNode)s);
            s["id"] = SwiftId(space.Id.Value);
            var profile = s["profile"] as JsonObject ?? new();
            profile["id"] = space.ProfileId.Value.ToString().ToUpperInvariant();
            if (profile.Parent is null) s["profile"] = profile;
            bool originallyProtected = Text(s["accessPolicy"]) is { } policy && policy != "open";
            if (originallyProtected != space.RequiresAuthentication)
                s["accessPolicy"] = space.RequiresAuthentication ? "deviceOwnerAuthentication" : "open";
            s["name"] = space.Name; s["symbol"] ??= "square.grid.2x2.fill"; s["accent"] ??= "indigo";
            s["selectedTabID"] = SwiftId(space.SelectedTabId?.Value);
            if (space.Search is { } search && searchPreferences.GetValueOrDefault(space.Id.Value) != search)
            {
                var preferences = s["browsingPreferences"] as JsonObject ?? new();
                if (preferences.Parent is null) s["browsingPreferences"] = preferences;
                preferences["selectedSearchProviderID"] = search.SelectedId;
                preferences["searchProvider"] = search.SelectedId.StartsWith("custom:", StringComparison.Ordinal) ? "google" : search.SelectedId;
                preferences["searchSuggestionsEnabled"] = search.SuggestionsEnabled;
                preferences["currentTabCleanupPolicy"] ??= "after12Hours";
                preferences["customSearchProviders"] = new JsonArray(search.CustomProviders.Select(p => (JsonNode)new JsonObject
                {
                    ["id"] = Guid.Parse(p.Id[7..]).ToString().ToUpperInvariant(), ["name"] = p.Name,
                    ["searchURLTemplate"] = p.SearchTemplate, ["suggestionURLTemplate"] = p.SuggestionTemplate
                }).ToArray());
            }
            if (space.Retention is { } retention && retentionPreferences.GetValueOrDefault(space.Id.Value) != retention)
            {
                var preferences = s["browsingPreferences"] as JsonObject ?? new();
                if (preferences.Parent is null) s["browsingPreferences"] = preferences;
                preferences["currentTabCleanupPolicy"] = EnumName(retention.CurrentTabs);
                var durations = preferences["dataRetention"] as JsonObject ?? new();
                if (durations.Parent is null) preferences["dataRetention"] = durations;
                durations["history"] = EnumName(retention.History); durations["archive"] = EnumName(retention.Archive);
                durations["downloads"] = EnumName(retention.Downloads);
            }
            if (!contentBlockingPolicies.TryGetValue(space.Id.Value, out var originalBlocking) || originalBlocking != space.ContentBlocking)
            {
                var preferences = s["browsingPreferences"] as JsonObject ?? new();
                if (preferences.Parent is null) s["browsingPreferences"] = preferences;
                preferences["contentBlockingPolicy"] = EnumName(space.ContentBlocking);
            }
            s["tabs"] = new JsonArray(space.Tabs.Select(t => (JsonNode)WriteTab(t)).ToArray());
            s["folders"] = new JsonArray(space.Folders.Select(f =>
            {
                var value = Copy(folders, f.Id.Value); value["id"] = SwiftId(f.Id.Value); value["title"] = f.Name;
                value["location"] = f.Location.ToString().ToLowerInvariant(); value["parentID"] = SwiftId(f.ParentId?.Value);
                value["isCollapsed"] = f.IsCollapsed; WriteDate(value, "collapseModifiedAt", f.CollapseModifiedAt);
                value["orderAnchorTabID"] = SwiftId(f.OrderAnchorTabId?.Value); return (JsonNode)value;
            }).ToArray());
            s["archivedTabs"] = new JsonArray(space.Archive.Select(a =>
            {
                var value = Copy(archives, a.Tab.Id.Value); value["tab"] = WriteTab(a.Tab);
                WriteDate(value, "archivedAt", a.ClosedAt); value["reason"] = a.Reason; return (JsonNode)value;
            }).ToArray());
            s["history"] = new JsonArray(space.History.Select(h =>
            {
                var value = Copy(histories, h.Id); value["id"] = h.Id.ToString().ToUpperInvariant();
                value["url"] = h.Url; value["title"] = h.Title; WriteDate(value, "firstVisitedAt", h.FirstVisitedAt);
                WriteDate(value, "lastVisitedAt", h.VisitedAt); value["visitCount"] = h.VisitCount; return (JsonNode)value;
            }).ToArray());
        }
        document["windows"] = new JsonArray(state.Windows.Select(w =>
        {
            var value = Copy(windows, w.Id.Value); value["id"] = SwiftId(w.Id.Value); value["selectedSpaceID"] = SwiftId(w.SpaceId.Value);
            if (w.PlatformSceneId is { } scene) value["platformSceneId"] = scene; else value.Remove("platformSceneId");
            var pairs = new JsonArray(); var captured = new JsonArray();
            foreach (var selection in w.Selections)
            {
                captured.Add((JsonNode)SwiftId(selection.Key.Value));
                if (selection.Value is { } tab) { pairs.Add((JsonNode)SwiftId(selection.Key.Value)); pairs.Add((JsonNode)SwiftId(tab.Value)); }
            }
            value["selectedTabIDsBySpace"] = pairs; value["capturedSpaceIDs"] = captured; return (JsonNode)value;
        }).ToArray());
        return document;
    }
}
