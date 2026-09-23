using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Shared preview/command implementation. Sources contain semantic records only;
/// positional asset references let the native caller retain opaque image bytes.
public sealed class NativeWorkspaceImport {
    #region Variables

    private sealed record Origin(int Source, int Space, int Tab, string Section);
    private readonly Dictionary<JsonNode, Origin> origins = new(ReferenceEqualityComparer.Instance);

    // The tab each imported Space should show first. It is a hint for the
    // window that ran the import, never a stored selection.
    private readonly Dictionary<JsonNode, Guid> shownTabs = new(ReferenceEqualityComparer.Instance);

    #endregion

    #region Actions - Workspace import

    private static Guid Id(JsonNode? n) => NativeSessionAuthority.Id(n);

    private static JsonArray Items(JsonNode n, string key) => n[key] as JsonArray ?? new();

    private static string Placement(JsonNode n) => n["placement"]?.GetValue<string>() ?? TabPlacementCodes.Current;

    private static JsonObject SwiftId(Guid id) => new() { ["rawValue"] = id.ToString("D") };

    private static Guid? OptionalId(JsonNode? n) => n is null ? null : Id(n);

    /// The imported session, positional asset references and the `selection`
    /// hint for the importing window, or `{"error": code}`.
    public static JsonObject Preview(JsonObject session, JsonObject arguments, string mode, double now) {
        try { return new NativeWorkspaceImport().Apply(LegacySelectionFields.WithoutSelection(session.DeepClone().AsObject()), arguments, WorkspaceImportModeCodes.Parse(mode), now); } catch (BrowserRuleException error) { return new() { ["error"] = error.Code }; }
    }

    private void Track(JsonNode space, int source, int index) {
        foreach (var section in new[] { StoredSessionCodec.Key.Tabs, StoredSessionCodec.Key.ArchivedTabs })
            for (int ti = 0; ti < Items(space, section).Count; ti++)
                origins[Items(space, section)[ti]!] = new(source, index, ti, section);
    }

    private JsonNode Copy(JsonNode node) {
        var copy = node.DeepClone();
        if (origins.TryGetValue(node, out var origin)) origins[copy] = origin;
        return copy;
    }

    private void Tabs(JsonNode space, IEnumerable<JsonNode> tabs) => space[StoredSessionCodec.Key.Tabs] = new JsonArray(tabs.Select(Copy).ToArray());

    private static void Customize(JsonNode space, JsonNode values) {
        space["name"] = SpaceOrganizationPolicy.Name(values["name"]!.GetValue<string>());
        space["symbol"] = SpaceOrganizationPolicy.Symbol(values["symbol"]!.GetValue<string>());
        space["accent"] = values["accent"]!.DeepClone();
        space["branding"] = values["branding"]!.DeepClone();
    }

    private static void Available(JsonNode session, Guid id) {
        if (Items(session, "spaceDeletions").Any(d => Id(d!["spaceID"]) == id))
            throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
    }

    private void ShowAdded(JsonNode space, IEnumerable<JsonNode> tabs) {
        var chosen = tabs.LastOrDefault(t => Placement(t) == TabPlacementCodes.Current) ?? tabs.FirstOrDefault();
        if (chosen is not null) shownTabs[space] = Id(chosen["id"]);
    }

    private JsonObject Apply(JsonObject source, JsonObject arguments, WorkspaceImportMode mode, double now) {
        var session = source.DeepClone().AsObject(); var spaces = Items(session, "spaces");
        var originalSpaces = new HashSet<JsonNode>(spaces.Select(s => s!), ReferenceEqualityComparer.Instance);
        Dictionary<JsonNode, HashSet<Guid>> originalFolderIds = new(ReferenceEqualityComparer.Instance);
        Dictionary<JsonNode, HashSet<Guid>> originalHistoryIds = new(ReferenceEqualityComparer.Instance);
        for (int si = 0; si < spaces.Count; si++) {
            var space = spaces[si]!;
            originalFolderIds[space] = Items(space, StoredSessionCodec.Key.Folders).Select(f => Id(f!["id"])).ToHashSet();
            originalHistoryIds[space] = Items(space, StoredSessionCodec.Key.History).Select(h => Id(h!["id"])).ToHashSet();
            Track(space, 0, si);
        }
        var inputs = Items(arguments, "sources").Select((n, i) => {
            var value = n!.DeepClone().AsObject();
            var requested = OptionalId(value[LegacySelectionFields.SelectedTab]);
            LegacySelectionFields.WithoutSpaceSelection(value);
            Track(value, i + 1, 0);
            if (requested is { } tab && Items(value, StoredSessionCodec.Key.Tabs).Any(t => Id(t!["id"]) == tab)) shownTabs[value] = tab;
            return value;
        }).ToArray();
        foreach (var input in inputs)
            WorkspaceImportPolicy.RequireSplitMembership(Items(input, StoredSessionCodec.Key.Tabs).Select(t => new SplitMember(OptionalId(t!["splitGroupID"]),
                TabPlacementCodes.Parse(Placement(t)) ?? TabPlacement.Saved, OptionalId(t["folderID"]))).ToArray());
        JsonNode? affected = null;
        if (mode == WorkspaceImportMode.Portable) {
            WorkspaceImportPolicy.RequireSpaceCapacity(spaces.Count, inputs.Length);
            foreach (var input in inputs) {
                // A Space the source did not say to show opens on its first tab.
                if (!shownTabs.ContainsKey(input) && Items(input, StoredSessionCodec.Key.Tabs).FirstOrDefault() is { } first)
                    shownTabs[input] = Id(first["id"]);
                spaces.Add((JsonNode)input);
            }
            affected = inputs.FirstOrDefault();
        } else if (mode == WorkspaceImportMode.Manual) {
            var drafts = Items(arguments, "drafts");
            WorkspaceImportPolicy.RequireSpaceCapacity(spaces.Count, drafts.Count(d => d!["isNew"]!.GetValue<bool>()));
            foreach (var draft in drafts) {
                var input = inputs[draft!["sourceIndex"]!.GetValue<int>()]; var id = Id(input["id"]);
                bool created = draft["isNew"]!.GetValue<bool>();
                var destination = created ? input : spaces.FirstOrDefault(s => Id(s!["id"]) == id);
                if (destination is null) continue; // A draft cannot recreate an existing Space deleted elsewhere.
                Available(session, id);
                if (!created && Id(destination["profile"]!["id"]) != Id(input["profile"]!["id"]))
                    throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
                if (created && spaces.Any(s => Id(s!["id"]) == id || Id(s["profile"]!["id"]) == Id(input["profile"]!["id"])))
                    throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
                Customize(destination, draft["customization"]!);
                var added = Items(input, StoredSessionCodec.Key.Tabs).Select(t => t!).ToArray();
                var old = created ? [] : Items(destination, StoredSessionCodec.Key.Tabs).Select(t => t!).ToArray();
                WorkspaceImportPolicy.RequirePinnedCapacity(old.Concat(added).Count(t => Placement(t) == TabPlacementCodes.Pinned));
                var ordered = new[] { TabPlacementCodes.Pinned, TabPlacementCodes.Saved, TabPlacementCodes.Current }.SelectMany(p => added.Where(t => Placement(t) == p)).ToArray();
                if (created) Tabs(destination, ordered);
                else {
                    var list = old.ToList();
                    var firstCurrent = list.FindIndex(t => Placement(t) == TabPlacementCodes.Current);
                    if (firstCurrent < 0) firstCurrent = list.Count;
                    var pinIndex = list.FindIndex(t => Placement(t) != TabPlacementCodes.Pinned);
                    if (pinIndex < 0) pinIndex = list.Count;
                    var pins = ordered.Where(t => Placement(t) == TabPlacementCodes.Pinned).ToArray();
                    list.InsertRange(pinIndex, pins);
                    list.InsertRange(firstCurrent + pins.Length, ordered.Where(t => Placement(t) == TabPlacementCodes.Saved));
                    list.AddRange(ordered.Where(t => Placement(t) == TabPlacementCodes.Current));
                    Tabs(destination, list);
                }
                ShowAdded(destination, created ? added : ordered);
                if (created) spaces.Add(destination);
                if (created || added.Length > 0) affected ??= destination;
            }
            if (arguments["orderWasEdited"]?.GetValue<bool>() == true) {
                var order = drafts.Select(d => Id(inputs[d!["sourceIndex"]!.GetValue<int>()]["id"])).ToArray();
                var sorted = order.Select(id => spaces.FirstOrDefault(s => Id(s!["id"]) == id)).OfType<JsonNode>()
                    .Concat(spaces.Where(s => !order.Contains(Id(s!["id"]))).Select(s => s!)).ToArray();
                spaces.Clear(); foreach (var space in sorted) spaces.Add(space);
            }
            session.Remove("disposableSeedMarker");
        } else if (mode == WorkspaceImportMode.Review) {
            var reviews = Items(arguments, "reviews").Where(r => r!["included"]!.GetValue<bool>()).ToArray();
            if (reviews.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.NoIncludedSpaces);
            bool replaceSeed = session["disposableSeedMarker"] is not null;
            WorkspaceImportPolicy.RequireSpaceCapacity(replaceSeed ? 0 : spaces.Count, reviews.Count(r => r!["destinationID"] is null));
            if (replaceSeed) {
                if (Items(session, "spaceDeletions").Count > 0) throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
                spaces.Clear(); session.Remove("defaultSpaceID");
            }
            foreach (var review in reviews) {
                var input = inputs[review!["sourceIndex"]!.GetValue<int>()];
                var destinationId = OptionalId(review["destinationID"]);
                var destination = destinationId is null ? input : spaces.FirstOrDefault(s => Id(s!["id"]) == destinationId);
                if (destination is null) continue;
                Available(session, Id(destination["id"]));
                Customize(destination, review["customization"]!);
                var included = Items(review, "includedTabIDs").Select(Id).ToHashSet();
                var overrides = Items(review, "placements").ToDictionary(n => Id(n!["tabID"]), n => n!["placement"]!.GetValue<string>());
                string PlacementFor(JsonNode tab) => overrides.GetValueOrDefault(Id(tab["id"]), Placement(tab));
                var additions = Items(input, StoredSessionCodec.Key.Tabs).Where(t => included.Contains(Id(t!["id"]))).Select(t => t!).ToArray();
                var sourceFolders = Items(input, StoredSessionCodec.Key.Folders);
                var folders = destinationId is null ? new JsonArray() : Items(destination, StoredSessionCodec.Key.Folders);
                var required = additions.Where(t => PlacementFor(t) == TabPlacementCodes.Saved && t["folderID"] is not null)
                    .Select(t => Id(t["folderID"])).ToHashSet();
                var byId = sourceFolders.ToDictionary(f => Id(f!["id"]), f => f!);
                var pending = new Stack<Guid>(required);
                while (pending.TryPop(out var id))
                    if (byId.TryGetValue(id, out var f) && OptionalId(f["parentID"]) is { } parent && required.Add(parent)) pending.Push(parent);
                var tree = FolderTree.RepairPreorder(sourceFolders.Select(f => new FolderState(Id(f!["id"]),
                    f["location"]?.GetValue<string>() == TabPlacementCodes.Current ? TabPlacement.Current : TabPlacement.Saved,
                    f["title"]!.GetValue<string>(), ParentId: OptionalId(f["parentID"]))).ToArray());
                Dictionary<Guid, Guid> mapping = [];
                foreach (var folder in tree.Where(f => required.Contains(f.Id))) {
                    var original = byId[folder.Id];
                    Guid? parent = folder.ParentId is { } p && mapping.TryGetValue(p, out var mapped) ? mapped : null;
                    var match = folders.FirstOrDefault(f => OptionalId(f!["parentID"]) == parent
                        && (f["location"]?.GetValue<string>() ?? TabPlacementCodes.Saved) == (original["location"]?.GetValue<string>() ?? TabPlacementCodes.Saved)
                        && WorkspaceImportPolicy.FolderMatchKey(f["title"]!.GetValue<string>()) == WorkspaceImportPolicy.FolderMatchKey(original["title"]!.GetValue<string>()));
                    if (match is not null) { mapping[folder.Id] = Id(match["id"]); continue; }
                    if (folders.Count >= WorkspaceImportPolicy.MaximumFolders) continue;
                    var copied = original.DeepClone().AsObject(); var identity = folder.Id;
                    copied.Remove("collapseModifiedAt"); copied.Remove("orderAnchorTabID");
                    while (folders.Any(f => Id(f!["id"]) == identity)) identity = Guid.NewGuid();
                    copied["id"] = SwiftId(identity); copied["parentID"] = parent is { } value ? SwiftId(value) : null;
                    copied["isCollapsed"] = false;
                    folders.Add((JsonNode)copied); mapping[folder.Id] = identity;
                }
                int pinned = destinationId is null ? 0 : Items(destination, StoredSessionCodec.Key.Tabs).Count(t => Placement(t!) == TabPlacementCodes.Pinned);
                var overflowFolder = folders.FirstOrDefault(f => string.Equals(f!["title"]!.GetValue<string>(), "Imported Pinned Tabs", StringComparison.OrdinalIgnoreCase));
                var edited = additions.Select(tab => {
                    var copy = Copy(tab); var placement = PlacementFor(tab); copy["placement"] = placement;
                    if (placement == TabPlacementCodes.Pinned && ++pinned > WorkspaceImportPolicy.MaximumPinnedTabs) {
                        copy["placement"] = placement = TabPlacementCodes.Saved;
                        if (overflowFolder is null && folders.Count < WorkspaceImportPolicy.MaximumFolders) {
                            overflowFolder = new JsonObject {
                                ["id"] = SwiftId(Guid.NewGuid()),
                                ["title"] = "Imported Pinned Tabs",
                                ["location"] = TabPlacementCodes.Saved,
                                ["symbol"] = "pin.slash",
                                ["isCollapsed"] = false
                            };
                            folders.Add(overflowFolder);
                        }
                        copy["folderID"] = overflowFolder?["id"]?.DeepClone();
                    } else copy["folderID"] = placement == TabPlacementCodes.Saved && OptionalId(tab["folderID"]) is { } old && mapping.TryGetValue(old, out var folder)
                          ? SwiftId(folder) : null;
                    copy["savedURL"] = placement == TabPlacementCodes.Current ? null : copy["savedURL"]?.DeepClone() ?? copy["url"]?.DeepClone();
                    if (placement == TabPlacementCodes.Pinned) copy["symbol"] = "pin.fill";
                    return copy;
                }).ToArray();
                destination[StoredSessionCodec.Key.Folders] = destinationId is null ? folders : folders.DeepClone();
                var existing = destinationId is null ? [] : Items(destination, StoredSessionCodec.Key.Tabs).Select(t => t!).ToArray();
                // The tab the source chose to show, when it was imported; a new
                // Space otherwise shows its first imported tab.
                Guid? requested = shownTabs.TryGetValue(input, out var chosen) ? chosen : null;
                var selected = edited.FirstOrDefault(t => Id(t["id"]) == requested);
                Tabs(destination, existing.Concat(edited));
                shownTabs.Remove(input);
                if ((selected ?? (destinationId is null ? edited.FirstOrDefault() : null)) is { } first)
                    shownTabs[destination] = Id(first["id"]);
                if (destinationId is null) spaces.Add(destination);
                affected ??= destination;
            }
            if (affected is not null) session.Remove("disposableSeedMarker");
        } else throw new BrowserRuleException(BrowserRuleCodes.UnknownWorkspaceCommand);
        // Folder and history record IDs are global in sync, even though their
        // native collections are nested under Spaces. Reserve existing IDs first
        // so an imported Space placed earlier cannot steal another Space's records.
        var folderIds = originalFolderIds.Values.SelectMany(ids => ids).ToHashSet();
        var historyIds = originalHistoryIds.Values.SelectMany(ids => ids).ToHashSet();
        foreach (var space in spaces.Select(s => s!)) {
            Dictionary<Guid, Guid> mapping = [];
            foreach (var folder in Items(space, StoredSessionCodec.Key.Folders)) {
                var old = Id(folder!["id"]); var id = old;
                if (!originalSpaces.Contains(space) || !originalFolderIds[space].Contains(old))
                    while (!folderIds.Add(id)) id = Guid.NewGuid();
                mapping.TryAdd(old, id); folder["id"] = SwiftId(id);
            }
            foreach (var folder in Items(space, StoredSessionCodec.Key.Folders))
                if (OptionalId(folder!["parentID"]) is { } parent && mapping.TryGetValue(parent, out var id)) folder["parentID"] = SwiftId(id);
            foreach (var tab in Items(space, StoredSessionCodec.Key.Tabs))
                if (OptionalId(tab!["folderID"]) is { } folder && mapping.TryGetValue(folder, out var id)) tab["folderID"] = SwiftId(id);
            foreach (var entry in Items(space, StoredSessionCodec.Key.History)) {
                var old = Id(entry!["id"]); var id = old;
                if (!originalSpaces.Contains(space) || !originalHistoryIds[space].Contains(old))
                    while (!historyIds.Add(id)) id = Guid.NewGuid();
                entry["id"] = id.ToString("D");
            }
        }
        int affectedIndex = affected is null ? -1 : spaces.IndexOf(affected);
        // Repair may replace colliding identities, so hints travel by position.
        var shown = new List<(int Space, int Tab)>();
        for (int si = 0; si < spaces.Count; si++)
            if (shownTabs.TryGetValue(spaces[si]!, out var tab)
                && Items(spaces[si]!, StoredSessionCodec.Key.Tabs).Select(t => Id(t!["id"])).ToList().IndexOf(tab) is var ti and >= 0)
                shown.Add((si, ti));
        var assets = new JsonArray();
        for (int si = 0; si < spaces.Count; si++)
            foreach (var section in new[] { StoredSessionCodec.Key.Tabs, StoredSessionCodec.Key.ArchivedTabs }) {
                int ti = 0;
                foreach (var node in Items(spaces[si]!, section)) {
                    if (section == StoredSessionCodec.Key.ArchivedTabs && node!["tab"]!["url"] is null && node["tab"]!["nativeContent"] is null) continue;
                    if (origins.TryGetValue(node!, out var origin)) assets.Add((JsonNode)new JsonObject {
                        ["spaceIndex"] = si,
                        ["tabIndex"] = ti,
                        ["section"] = section,
                        ["sourceIndex"] = origin.Source,
                        ["sourceSpaceIndex"] = origin.Space,
                        ["sourceTabIndex"] = origin.Tab
                    });
                    ti++;
                }
            }
        var repaired = NativeSessionMaintenance.Repair(session, now);
        // Show the imported instance even when repair replaced a colliding ID.
        var repairedSpaces = Items(repaired["session"]!, "spaces");
        var hint = new SessionSelectionHint();
        if (affectedIndex >= 0) hint.SelectSpace(Id(repairedSpaces[affectedIndex]!["id"]));
        foreach (var (si, ti) in shown)
            hint.SelectTab(SessionView.Empty, Id(repairedSpaces[si]!["id"]), Id(Items(repairedSpaces[si]!, StoredSessionCodec.Key.Tabs)[ti]!["id"]));
        repaired["assets"] = assets;
        repaired[SessionSelectionHint.Key] = hint.Encode();
        return repaired;
    }

    #endregion
}
