using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Reads Crest's existing Swift Codable session. Unowned/additive fields survive
/// round trips verbatim as JSON values; only fields owned by the domain are replaced.
public sealed class LegacySessionDocument {
    #region Variables

    private static readonly DateTimeOffset SwiftEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private readonly JsonObject original;
    private readonly Dictionary<Guid, JsonObject> spaces = [];
    private readonly Dictionary<Guid, SessionTabRecord> tabs = [];
    private readonly Dictionary<Guid, JsonObject> folders = [];
    private readonly Dictionary<Guid, JsonObject> archives = [];
    private readonly Dictionary<Guid, JsonObject> histories = [];
    private readonly Dictionary<Guid, JsonObject> windows = [];
    private readonly Dictionary<Guid, SearchPreferences> searchPreferences = [];
    private readonly Dictionary<Guid, RetentionPreferences> retentionPreferences = [];
    private readonly Dictionary<Guid, ContentBlockingPolicy> contentBlockingPolicies = [];

    #endregion

    #region Constructors

    public LegacySessionDocument(JsonObject? source = null) => original = (JsonObject?)source?.DeepClone() ?? new();

    #endregion

    #region Actions - Session records

    public void CopyTabMetadata(Guid source, Guid destination) {
        if (tabs.TryGetValue(source, out var value)) tabs[destination] = value.Copy();
    }

    internal void TransferTabMetadata(Guid tab, LegacySessionDocument destination) {
        if (tabs.TryGetValue(tab, out var value)) destination.tabs[tab] = value.Copy();
    }

    private static JsonObject Copy(Dictionary<Guid, JsonObject> originals, Guid id)
        => originals.TryGetValue(id, out var value) ? (JsonObject)value.DeepClone() : new();

    private static void Remember<T>(Dictionary<Guid, T> values, Guid id, T value) {
        if (!values.TryAdd(id, value)) throw new BrowserRuleException(BrowserRuleCodes.DuplicatePersistedIdentity);
    }

    private SessionTabRecord TabRecord(TabState tab) => tabs.GetValueOrDefault(tab.Id) ?? new();

    #endregion

    #region Actions - Decoding

    private static JsonObject Object(JsonNode? node) => node as JsonObject ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedState);

    private static JsonArray Array(JsonNode? node) => node is null ? [] : node as JsonArray ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedState);

    internal static string? Text(JsonNode? node) => node is null ? null : node.GetValue<string>();

    internal static Guid Id(JsonNode? node) {
        if (node is JsonObject o) node = o["rawValue"];
        if (!Guid.TryParseExact(Text(node), "D", out var id) || id == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedIdentity);
        return id;
    }

    internal static Guid? OptionalId(JsonNode? node) => node is null ? null : Id(node);

    internal static DateTimeOffset Date(JsonNode? node) {
        var seconds = node?.GetValue<double>() ?? 0;
        if (!double.IsFinite(seconds)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedDate);
        return SwiftEpoch.AddSeconds(seconds);
    }

    internal static DateTimeOffset? OptionalDate(JsonNode? node) => node is null ? null : Date(node);

    internal static TabPlacement Placement(JsonNode? node)
        => TabPlacementCodes.Parse(Text(node)) ?? TabPlacement.Saved;

    private TabState ReadTab(JsonObject tab) {
        var record = new SessionTabRecord(tab);
        var state = record.Decode();
        Remember(tabs, state.Id, record);
        return state;
    }

    internal TabState ReadNewTab(SessionTabRecord record) {
        var state = record.Decode();
        Remember(tabs, state.Id, record);
        return state;
    }

    public WorkspaceState Read(IIdSource ids) {
        spaces.Clear(); tabs.Clear(); folders.Clear(); archives.Clear(); histories.Clear(); windows.Clear(); searchPreferences.Clear(); retentionPreferences.Clear();
        var session = Object(original["session"]);
        var states = new List<SpaceState>();
        foreach (var value in Array(session["spaces"])) {
            var s = Object(value); var id = Id(s["id"]); Remember(spaces, id, s);
            var folderStates = new List<FolderState>();
            foreach (var fv in Array(s["folders"])) {
                var f = Object(fv); var fid = Id(f["id"]); Remember(folders, fid, f);
                var parent = OptionalId(f["parentID"]);
                folderStates.Add(new(fid, Text(f["title"]) ?? "Folder", Text(f["location"]) == TabPlacementCodes.Current ? TabPlacement.Current : TabPlacement.Saved,
                    parent, f["isCollapsed"]?.GetValue<bool>() ?? false,
                    OptionalDate(f["collapseModifiedAt"]), OptionalId(f["orderAnchorTabID"])));
            }
            var archived = new List<ArchiveState>();
            foreach (var av in Array(s["archivedTabs"])) {
                var a = Object(av); var tab = ReadTab(Object(a["tab"])); Remember(archives, tab.Id, a);
                archived.Add(new(tab, Date(a["archivedAt"]), Text(a["reason"]) ?? ArchiveReasons.Closed));
            }
            var visits = new List<HistoryVisit>();
            foreach (var hv in Array(s["history"])) {
                var h = Object(hv); var hid = Id(h["id"]); Remember(histories, hid, h);
                visits.Add(new(hid, Text(h["url"]) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedUrl), Text(h["title"]) ?? "",
                    Date(h["firstVisitedAt"]), Date(h["lastVisitedAt"]), h["visitCount"]?.GetValue<int>() ?? 1));
            }
            var selected = OptionalId(s["selectedTabID"]);
            var preferences = s["browsingPreferences"] as JsonObject;
            var customProviders = new List<SearchProvider>();
            foreach (var item in Array(preferences?["customSearchProviders"])) {
                try {
                    var custom = Object(item);
                    customProviders.Add(SearchProvider.Custom(Id(custom["id"]), Text(custom["name"]) ?? "",
                        Text(custom["searchURLTemplate"]) ?? "", Text(custom["suggestionURLTemplate"])));
                } catch (BrowserRuleException) { /* Invalid legacy custom providers are excluded just as in Swift. */ }
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
            states.Add(new(id, Id(Object(s["profile"])["id"]), Text(s["name"]) ?? "Space",
                Text(s["accessPolicy"]) is { } policy && policy != SpaceAccessPolicyCodes.Open,
                Array(s["tabs"]).Select(t => ReadTab(Object(t))).ToArray(), folderStates, archived, visits,
                selected, search,
                Text(s["accessPolicy"]) is null or SpaceAccessPolicyCodes.Open or SpaceAccessPolicyCodes.DeviceOwnerAuthentication, retention,
                ReadEnum(preferences?["contentBlockingPolicy"], ContentBlockingPolicy.Balanced, ContentBlockingPolicy.Balanced)));
        }
        var windowStates = new List<WindowState>();
        foreach (var value in Array(original["windows"])) {
            var w = Object(value); var id = Id(w["id"]); Remember(windows, id, w);
            var selections = new Dictionary<Guid, Guid?>();
            // Codable dictionaries with struct keys use an alternating key/value array.
            var pairs = Array(w["selectedTabIDsBySpace"]);
            if (pairs.Count % 2 != 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedSelection);
            for (int index = 0; index < pairs.Count; index += 2)
                selections.Add(Id(pairs[index]), Id(pairs[index + 1]));
            if (w["capturedSpaceIDs"] is not null)
                foreach (var captured in Array(w["capturedSpaceIDs"])) selections.TryAdd(Id(captured), null);
            else
                foreach (var space in states) selections.TryAdd(space.Id, space.SelectedTabId);
            windowStates.Add(new(id, Id(w["selectedSpaceID"]), selections, Text(w["platformSceneId"])));
        }
        var defaultId = OptionalId(session["defaultSpaceID"]);
        var selectedId = OptionalId(session["selectedSpaceID"]);
        var deletions = Array(original["spaceDeletions"]).Select(value => {
            var deletion = Object(value);
            return new SpaceDeletionState(Id(deletion["spaceId"]), Id(deletion["profileId"]),
                Date(deletion["requestedAt"]), deletion["completed"]?.GetValue<bool>() ?? false);
        }).ToArray();
        return new(OptionalId(original["workspaceId"]) ?? ids.Next(), defaultId,
            selectedId, states, windowStates, deletions);
    }

    private static T ReadEnum<T>(JsonNode? value, T missing, T unknown) where T : struct, Enum
        => value is null ? missing : Enum.TryParse<T>(Text(value), true, out var result) && Enum.IsDefined(result) ? result : unknown;

    #endregion

    #region Actions - Encoding

    internal static JsonObject SwiftId(Guid id) => new() { ["rawValue"] = id.ToString().ToUpperInvariant() };

    internal static JsonNode? SwiftId(Guid? id) => id is { } value ? SwiftId(value) : null;

    private static double Seconds(DateTimeOffset date) => (date - SwiftEpoch).TotalSeconds;

    internal static void WriteDate(JsonObject value, string key, DateTimeOffset? date, bool editTimestamp = false) {
        // Swift Date stores a Double, with precision that differs from .NET ticks.
        // Preserve its original number when the domain has not changed this field.
        if (date is { } d && value[key] is { } originalDate && Date(originalDate) == d) return;
        value[key] = date is { } updated ? editTimestamp ? NativeEditTimestamp.Encode(updated) : Seconds(updated) : null;
    }

    internal static string EnumName<T>(T value) where T : struct, Enum { var text = value.ToString(); return char.ToLowerInvariant(text[0]) + text[1..]; }

    public JsonObject Write(WorkspaceState state) {
        var document = (JsonObject)original.DeepClone();
        var session = document["session"] as JsonObject ?? new();
        if (session.Parent is null) document["session"] = session;
        document["workspaceId"] = state.Id.ToString(); document["formatVersion"] = 1;
        document["spaceDeletions"] = new JsonArray((state.SpaceDeletions ?? []).Select(d => (JsonNode)new JsonObject {
            ["spaceId"] = d.Space.ToString(),
            ["profileId"] = d.Profile.ToString(),
            ["requestedAt"] = Seconds(d.RequestedAt),
            ["completed"] = d.Completed
        }).ToArray());
        session["selectedSpaceID"] = SwiftId(state.SelectedSpaceId);
        session["defaultSpaceID"] = SwiftId(state.DefaultSpaceId);
        var spaceValues = new JsonArray(); session["spaces"] = spaceValues;
        foreach (var space in state.Spaces) {
            var s = Copy(spaces, space.Id); spaceValues.Add((JsonNode)s);
            s["id"] = SwiftId(space.Id);
            var profile = s["profile"] as JsonObject ?? new();
            profile["id"] = space.ProfileId.ToString().ToUpperInvariant();
            if (profile.Parent is null) s["profile"] = profile;
            bool originallyProtected = Text(s["accessPolicy"]) is { } policy && policy != SpaceAccessPolicyCodes.Open;
            if (originallyProtected != space.RequiresAuthentication)
                s["accessPolicy"] = space.RequiresAuthentication ? SpaceAccessPolicyCodes.DeviceOwnerAuthentication : SpaceAccessPolicyCodes.Open;
            s["name"] = space.Name; s["symbol"] ??= "square.grid.2x2.fill"; s["accent"] ??= SpaceAccentCodes.Indigo;
            s["selectedTabID"] = SwiftId(space.SelectedTabId);
            if (space.Search is { } search && searchPreferences.GetValueOrDefault(space.Id) != search) {
                var preferences = s["browsingPreferences"] as JsonObject ?? new();
                if (preferences.Parent is null) s["browsingPreferences"] = preferences;
                preferences["selectedSearchProviderID"] = search.SelectedId;
                preferences["searchProvider"] = search.SelectedId.StartsWith("custom:", StringComparison.Ordinal) ? "google" : search.SelectedId;
                preferences["searchSuggestionsEnabled"] = search.SuggestionsEnabled;
                preferences["currentTabCleanupPolicy"] ??= "after12Hours";
                preferences["customSearchProviders"] = new JsonArray(search.CustomProviders.Select(p => (JsonNode)new JsonObject {
                    ["id"] = Guid.Parse(p.Id[7..]).ToString().ToUpperInvariant(),
                    ["name"] = p.Name,
                    ["searchURLTemplate"] = p.SearchTemplate,
                    ["suggestionURLTemplate"] = p.SuggestionTemplate
                }).ToArray());
            }
            if (space.Retention is { } retention && retentionPreferences.GetValueOrDefault(space.Id) != retention) {
                var preferences = s["browsingPreferences"] as JsonObject ?? new();
                if (preferences.Parent is null) s["browsingPreferences"] = preferences;
                preferences["currentTabCleanupPolicy"] = EnumName(retention.CurrentTabs);
                var durations = preferences["dataRetention"] as JsonObject ?? new();
                if (durations.Parent is null) preferences["dataRetention"] = durations;
                durations["history"] = EnumName(retention.History); durations["archive"] = EnumName(retention.Archive);
                durations["downloads"] = EnumName(retention.Downloads);
            }
            if (!contentBlockingPolicies.TryGetValue(space.Id, out var originalBlocking) || originalBlocking != space.ContentBlocking) {
                var preferences = s["browsingPreferences"] as JsonObject ?? new();
                if (preferences.Parent is null) s["browsingPreferences"] = preferences;
                preferences["contentBlockingPolicy"] = EnumName(space.ContentBlocking);
            }
            s["tabs"] = new JsonArray(space.Tabs.Select(tab => (JsonNode)TabRecord(tab).Encode(tab)).ToArray());
            s["folders"] = new JsonArray(space.Folders.Select(f => {
                var value = Copy(folders, f.Id); value["id"] = SwiftId(f.Id); value["title"] = f.Name;
                value["location"] = TabPlacementCodes.Name(f.Location); value["parentID"] = SwiftId(f.ParentId);
                value["isCollapsed"] = f.IsCollapsed; WriteDate(value, "collapseModifiedAt", f.CollapseModifiedAt);
                value["orderAnchorTabID"] = SwiftId(f.OrderAnchorTabId); return (JsonNode)value;
            }).ToArray());
            s["archivedTabs"] = new JsonArray(space.Archive.Select(a => {
                var value = Copy(archives, a.Tab.Id); value["tab"] = TabRecord(a.Tab).Encode(a.Tab);
                WriteDate(value, "archivedAt", a.ClosedAt); value["reason"] = a.Reason; return (JsonNode)value;
            }).ToArray());
            s["history"] = new JsonArray(space.History.Select(h => {
                var value = Copy(histories, h.Id); value["id"] = h.Id.ToString().ToUpperInvariant();
                value["url"] = h.Url; value["title"] = h.Title; WriteDate(value, "firstVisitedAt", h.FirstVisitedAt);
                WriteDate(value, "lastVisitedAt", h.VisitedAt); value["visitCount"] = h.VisitCount; return (JsonNode)value;
            }).ToArray());
        }
        document["windows"] = new JsonArray(state.Windows.Select(w => {
            var value = Copy(windows, w.Id); value["id"] = SwiftId(w.Id); value["selectedSpaceID"] = SwiftId(w.SpaceId);
            if (w.PlatformSceneId is { } scene) value["platformSceneId"] = scene; else value.Remove("platformSceneId");
            var pairs = new JsonArray(); var captured = new JsonArray();
            foreach (var selection in w.Selections) {
                captured.Add((JsonNode)SwiftId(selection.Key));
                if (selection.Value is { } tab) { pairs.Add((JsonNode)SwiftId(selection.Key)); pairs.Add((JsonNode)SwiftId(tab)); }
            }
            value["selectedTabIDsBySpace"] = pairs; value["capturedSpaceIDs"] = captured; return (JsonNode)value;
        }).ToArray());
        return document;
    }

    #endregion

    #region Mutators

    /// Appearance fields the domain does not model travel verbatim through the
    /// tab record. Reading and writing them here keeps the rules that decide
    /// them in one place without giving the domain an image cache.
    internal JsonNode? TabMetadata(Guid id, string field)
        => tabs.TryGetValue(id, out var record) ? record.Metadata(field) : null;

    internal bool SetTabMetadata(Guid id, string field, JsonNode? value) {
        if (!tabs.TryGetValue(id, out var record)) tabs[id] = record = new();
        return record.SetMetadata(field, value);
    }

    internal bool SetFolderMetadata(Guid id, string field, JsonNode value) {
        if (!folders.TryGetValue(id, out var metadata)) folders[id] = metadata = new();
        if (JsonNode.DeepEquals(metadata[field], value)) return false;
        metadata[field] = value.DeepClone();
        return true;
    }

    #endregion
}
