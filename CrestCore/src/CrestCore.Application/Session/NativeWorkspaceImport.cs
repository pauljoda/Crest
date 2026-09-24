using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using Key = CrestCore.Application.StoredSessionCodec.Key;

namespace CrestCore.Application;

/// Shared preview/command implementation. Sources contain semantic records only;
/// positional asset references let the native caller retain opaque image bytes.
public sealed class NativeWorkspaceImport {
    #region Variables

    /// Where an imported or existing tab record came from: its source (0 for the
    /// session, else the source's position after one), Space, position and section.
    private sealed record Origin(int Source, int Space, int Tab, string Section);

    /// A Space while the import edits it. Spaces are compared by this holder, so a
    /// Space keeps its place in the import as its record is replaced.
    private sealed class Draft(SpaceState state, bool isOriginal) {
        public SpaceState State { get; set; } = state;
        public bool IsOriginal { get; } = isOriginal;
        public Guid Id => State.Id;

        // The tab this Space should show first. It is a hint for the window that
        // ran the import, never a stored selection.
        public Guid? ShownTab { get; set; }
    }

    // Tab and archive records by reference, so two records that share an identity
    // keep their own origins.
    private readonly Dictionary<object, Origin> origins = new(ReferenceEqualityComparer.Instance);

    #endregion

    #region Actions - Workspace import

    /// The imported session, positional asset references and the `selection`
    /// hint for the importing window, or `{"error": code}`.
    public static JsonObject Preview(JsonObject session, JsonObject arguments, string mode, double now) {
        try {
            return Preview(StoredSessionCodec.DecodeSession(session), arguments, mode, now).Answer;
        } catch (BrowserRuleException error) {
            return new() { ["error"] = error.Code };
        }
    }

    /// The imported session with its answer, or no session and `{"error": code}`.
    /// `followUp` takes what the importing window shows next.
    internal static (SessionState? Session, JsonObject Answer) Preview(SessionState session, JsonObject arguments, string mode, double now,
        WindowFollowUp? followUp = null) {
        try {
            if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedDate);
            var import = new NativeWorkspaceImport();
            var imported = import.Apply(session, arguments, WorkspaceImportModeCodes.Parse(mode), StoredSessionCodec.Date(now),
                followUp ?? new WindowFollowUp(window: null), out var answer);
            return (imported, answer);
        } catch (BrowserRuleException error) {
            return (null, new() { ["error"] = error.Code });
        }
    }

    private static Guid Id(JsonNode? n) => NativeSessionAuthority.Id(n);

    private static Guid? OptionalId(JsonNode? n) => n is null ? null : Id(n);

    private static JsonArray Items(JsonNode n, string key) => n[key] as JsonArray ?? new();

    private void Track(SpaceState space, int source, int index) {
        foreach (var (tab, position) in space.Tabs.Select((tab, position) => (tab, position)))
            origins[tab] = new(source, index, position, Key.Tabs);
        foreach (var (archived, position) in space.ArchivedTabs.Select((archived, position) => (archived, position)))
            origins[archived] = new(source, index, position, Key.ArchivedTabs);
    }

    /// A changed copy of a tab keeps the tab's origin.
    private TabState Copied(TabState tab, TabState copy) {
        if (origins.TryGetValue(tab, out var origin)) origins[copy] = origin;
        return copy;
    }

    private static void Customize(Draft space, JsonNode values) => space.State = space.State with {
        Name = SpaceOrganizationPolicy.Name(values[Key.Name]!.GetValue<string>()),
        Symbol = SpaceOrganizationPolicy.Symbol(values[Key.Symbol]!.GetValue<string>()),
        Accent = StoredSessionCodec.DecodeAccent(values[Key.Accent]),
        Branding = values[Key.Branding] is JsonObject branding ? StoredSessionCodec.DecodeBranding(branding) : null
    };

    private static void Available(SessionState session, Guid id) {
        if (session.SpaceDeletions.Any(deletion => deletion.SpaceId == id))
            throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
    }

    private static void ShowAdded(Draft space, IEnumerable<TabState> tabs) {
        var chosen = tabs.LastOrDefault(t => t.Placement == TabPlacement.Current) ?? tabs.FirstOrDefault();
        if (chosen is not null) space.ShownTab = chosen.Id;
    }

    private SessionState Apply(SessionState session, JsonObject arguments, WorkspaceImportMode mode, DateTimeOffset now,
        WindowFollowUp followUp, out JsonObject answer) {
        var spaces = session.Spaces.Select(space => new Draft(space, isOriginal: true)).ToList();
        var defaultSpace = session.DefaultSpaceId;
        var seedMarker = session.DisposableSeedMarker;
        for (int si = 0; si < spaces.Count; si++) Track(spaces[si].State, 0, si);
        var originalFolderIds = spaces.ToDictionary(space => space, space => space.State.Folders.Select(f => f.Id).ToHashSet());
        var originalHistoryIds = spaces.ToDictionary(space => space, space => space.State.History.Select(h => h.Id).ToHashSet());
        var inputs = Items(arguments, "sources").Select((node, i) => {
            var requested = StoredSessionCodec.LegacySelectedTab(node);
            var input = new Draft(StoredSessionCodec.DecodeSpace(node), isOriginal: false);
            Track(input.State, i + 1, 0);
            if (requested is { } tab && input.State.Tabs.Any(t => t.Id == tab)) input.ShownTab = tab;
            return input;
        }).ToArray();
        foreach (var input in inputs)
            WorkspaceImportPolicy.RequireSplitMembership(input.State.Tabs.Select(t => new SplitMember(t.SplitGroupId, t.Placement, t.FolderId)).ToArray());
        Draft? affected = null;
        if (mode == WorkspaceImportMode.Portable) {
            WorkspaceImportPolicy.RequireSpaceCapacity(spaces.Count, inputs.Length);
            foreach (var input in inputs) {
                // A Space the source did not say to show opens on its first tab.
                if (input.ShownTab is null && input.State.Tabs.FirstOrDefault() is { } first) input.ShownTab = first.Id;
                spaces.Add(input);
            }
            affected = inputs.FirstOrDefault();
        } else if (mode == WorkspaceImportMode.Manual) {
            var drafts = Items(arguments, "drafts");
            WorkspaceImportPolicy.RequireSpaceCapacity(spaces.Count, drafts.Count(d => d!["isNew"]!.GetValue<bool>()));
            foreach (var draft in drafts) {
                var input = inputs[draft!["sourceIndex"]!.GetValue<int>()]; var id = input.Id;
                bool created = draft["isNew"]!.GetValue<bool>();
                var destination = created ? input : spaces.FirstOrDefault(s => s.Id == id);
                if (destination is null) continue; // A draft cannot recreate an existing Space deleted elsewhere.
                Available(session, id);
                if (!created && destination.State.ProfileId != input.State.ProfileId)
                    throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
                if (created && spaces.Any(s => s.Id == id || s.State.ProfileId == input.State.ProfileId))
                    throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
                Customize(destination, draft["customization"]!);
                var added = input.State.Tabs.ToArray();
                var old = created ? [] : destination.State.Tabs.ToArray();
                WorkspaceImportPolicy.RequirePinnedCapacity(old.Concat(added).Count(t => t.Placement == TabPlacement.Pinned));
                var ordered = new[] { TabPlacement.Pinned, TabPlacement.Saved, TabPlacement.Current }
                    .SelectMany(p => added.Where(t => t.Placement == p)).ToArray();
                if (created) destination.State = destination.State with { Tabs = ordered };
                else {
                    var list = old.ToList();
                    var firstCurrent = list.FindIndex(t => t.Placement == TabPlacement.Current);
                    if (firstCurrent < 0) firstCurrent = list.Count;
                    var pinIndex = list.FindIndex(t => t.Placement != TabPlacement.Pinned);
                    if (pinIndex < 0) pinIndex = list.Count;
                    var pins = ordered.Where(t => t.Placement == TabPlacement.Pinned).ToArray();
                    list.InsertRange(pinIndex, pins);
                    list.InsertRange(firstCurrent + pins.Length, ordered.Where(t => t.Placement == TabPlacement.Saved));
                    list.AddRange(ordered.Where(t => t.Placement == TabPlacement.Current));
                    destination.State = destination.State with { Tabs = list.ToArray() };
                }
                ShowAdded(destination, created ? added : ordered);
                if (created) spaces.Add(destination);
                if (created || added.Length > 0) affected ??= destination;
            }
            if (arguments["orderWasEdited"]?.GetValue<bool>() == true) {
                var order = drafts.Select(d => inputs[d!["sourceIndex"]!.GetValue<int>()].Id).ToArray();
                spaces = order.Select(id => spaces.FirstOrDefault(s => s.Id == id)).OfType<Draft>()
                    .Concat(spaces.Where(s => !order.Contains(s.Id))).ToList();
            }
            seedMarker = null;
        } else if (mode == WorkspaceImportMode.Review) {
            var reviews = Items(arguments, "reviews").Where(r => r!["included"]!.GetValue<bool>()).ToArray();
            if (reviews.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.NoIncludedSpaces);
            bool replaceSeed = seedMarker is not null;
            WorkspaceImportPolicy.RequireSpaceCapacity(replaceSeed ? 0 : spaces.Count, reviews.Count(r => r!["destinationID"] is null));
            if (replaceSeed) {
                if (session.SpaceDeletions.Count > 0) throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
                spaces.Clear(); defaultSpace = null;
            }
            foreach (var review in reviews) {
                var input = inputs[review!["sourceIndex"]!.GetValue<int>()];
                var destinationId = OptionalId(review["destinationID"]);
                var destination = destinationId is null ? input : spaces.FirstOrDefault(s => s.Id == destinationId);
                if (destination is null) continue;
                Available(session, destination.Id);
                Customize(destination, review["customization"]!);
                Import(review, input, destination, isNew: destinationId is null);
                if (destinationId is null) spaces.Add(destination);
                affected ??= destination;
            }
            if (affected is not null) seedMarker = null;
        } else throw new BrowserRuleException(BrowserRuleCodes.UnknownWorkspaceCommand);
        // Folder and history record IDs are global in sync, even though their
        // native collections are nested under Spaces. Reserve existing IDs first
        // so an imported Space placed earlier cannot steal another Space's records.
        var folderIds = originalFolderIds.Values.SelectMany(ids => ids).ToHashSet();
        var historyIds = originalHistoryIds.Values.SelectMany(ids => ids).ToHashSet();
        foreach (var space in spaces) Reserve(space, space.IsOriginal ? originalFolderIds[space] : null,
            space.IsOriginal ? originalHistoryIds[space] : null, folderIds, historyIds);
        int affectedIndex = affected is null ? -1 : spaces.IndexOf(affected);
        // Repair may replace colliding identities, so hints travel by position.
        var shown = new List<(int Space, int Tab)>();
        for (int si = 0; si < spaces.Count; si++)
            if (spaces[si].ShownTab is { } tab && spaces[si].State.Tabs.Select(t => t.Id).ToList().IndexOf(tab) is var ti and >= 0)
                shown.Add((si, ti));
        var assets = Assets(spaces);
        var imported = session with {
            Spaces = spaces.Select(space => space.State).ToArray(),
            DefaultSpaceId = defaultSpace,
            DisposableSeedMarker = seedMarker
        };
        var repaired = NativeSessionMaintenance.Repair(imported, now, null, new SystemIdSource(), out _);
        // Show the imported instance even when repair replaced a colliding ID.
        if (affectedIndex >= 0) followUp.ShowSpace(repaired.Spaces[affectedIndex].Id);
        foreach (var (si, ti) in shown) followUp.ShowTab(repaired.Spaces[si].Id, repaired.Spaces[si].Tabs[ti].Id);
        answer = new() {
            ["session"] = StoredSessionCodec.Encode(repaired),
            ["assets"] = assets
        };
        return repaired;
    }

    /// A reviewed Space's included tabs, in the placements the review chose, with
    /// the saved folders they need. Pinned tabs past the limit become saved tabs
    /// in the overflow folder.
    private void Import(JsonNode review, Draft input, Draft destination, bool isNew) {
        var included = Items(review, "includedTabIDs").Select(Id).ToHashSet();
        var overrides = Items(review, "placements").ToDictionary(n => Id(n!["tabID"]),
            n => TabPlacementCodes.Parse(n!["placement"]!.GetValue<string>()) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidPlacement));
        TabPlacement PlacementFor(TabState tab) => overrides.GetValueOrDefault(tab.Id, tab.Placement);
        var additions = input.State.Tabs.Where(t => included.Contains(t.Id)).ToArray();
        var sourceFolders = input.State.Folders;
        var folders = isNew ? [] : destination.State.Folders.ToList();
        var required = additions.Where(t => PlacementFor(t) == TabPlacement.Saved && t.FolderId is not null)
            .Select(t => t.FolderId!.Value).ToHashSet();
        var byId = sourceFolders.GroupBy(f => f.Id).ToDictionary(g => g.Key, g => g.First());
        var pending = new Stack<Guid>(required);
        while (pending.TryPop(out var id))
            if (byId.TryGetValue(id, out var f) && f.ParentId is { } parent && required.Add(parent)) pending.Push(parent);
        Dictionary<Guid, Guid> mapping = [];
        foreach (var folder in FolderTree.RepairPreorder(sourceFolders).Where(f => required.Contains(f.Id))) {
            var original = byId[folder.Id];
            Guid? parent = folder.ParentId is { } p && mapping.TryGetValue(p, out var mapped) ? mapped : null;
            var match = folders.FirstOrDefault(f => f.ParentId == parent && f.Location == original.Location
                && WorkspaceImportPolicy.FolderMatchKey(f.Title) == WorkspaceImportPolicy.FolderMatchKey(original.Title));
            if (match is not null) { mapping[folder.Id] = match.Id; continue; }
            if (folders.Count >= WorkspaceImportPolicy.MaximumFolders) continue;
            var identity = folder.Id;
            while (folders.Any(f => f.Id == identity)) identity = Guid.NewGuid();
            folders.Add(original with {
                Id = identity,
                ParentId = parent,
                IsCollapsed = false,
                CollapseModifiedAt = null,
                OrderAnchorTabId = null
            });
            mapping[folder.Id] = identity;
        }
        int pinned = isNew ? 0 : destination.State.Tabs.Count(t => t.Placement == TabPlacement.Pinned);
        var overflowFolder = folders.FirstOrDefault(f =>
            string.Equals(f.Title, WorkspaceImportPolicy.OverflowFolderTitle, StringComparison.OrdinalIgnoreCase));
        var edited = additions.Select(tab => {
            var placement = PlacementFor(tab);
            Guid? folder;
            if (placement == TabPlacement.Pinned && ++pinned > WorkspaceImportPolicy.MaximumPinnedTabs) {
                placement = TabPlacement.Saved;
                if (overflowFolder is null && folders.Count < WorkspaceImportPolicy.MaximumFolders) {
                    overflowFolder = new FolderState(Guid.NewGuid(), TabPlacement.Saved, WorkspaceImportPolicy.OverflowFolderTitle,
                        WorkspaceImportPolicy.OverflowFolderSymbol);
                    folders.Add(overflowFolder);
                }
                folder = overflowFolder?.Id;
            } else folder = placement == TabPlacement.Saved && tab.FolderId is { } old && mapping.TryGetValue(old, out var copied)
                  ? copied : null;
            return Copied(tab, tab with {
                Placement = placement,
                FolderId = folder,
                SavedUrl = placement == TabPlacement.Current ? null : tab.SavedUrl ?? tab.Url,
                Symbol = placement == TabPlacement.Pinned ? ManualSetupPolicy.PinnedTabSymbol : tab.Symbol
            });
        }).ToArray();
        var existing = isNew ? [] : destination.State.Tabs;
        // The tab the source chose to show, when it was imported; a new Space
        // otherwise shows its first imported tab.
        var selected = edited.FirstOrDefault(t => t.Id == input.ShownTab);
        destination.State = destination.State with { Folders = folders.ToArray(), Tabs = [.. existing, .. edited] };
        input.ShownTab = null;
        if ((selected ?? (isNew ? edited.FirstOrDefault() : null)) is { } first) destination.ShownTab = first.Id;
    }

    /// Gives a Space's folders and history identities no other Space holds,
    /// keeping the ones it had before the import, and points its folder
    /// references at the new folder identities.
    private void Reserve(Draft space, HashSet<Guid>? originalFolders, HashSet<Guid>? originalHistory,
        HashSet<Guid> folderIds, HashSet<Guid> historyIds) {
        Dictionary<Guid, Guid> mapping = [];
        var folders = space.State.Folders.Select(folder => {
            var id = folder.Id;
            if (originalFolders?.Contains(folder.Id) != true)
                while (!folderIds.Add(id)) id = Guid.NewGuid();
            mapping.TryAdd(folder.Id, id);
            return folder with { Id = id };
        }).ToArray();
        Guid? Mapped(Guid? id) => id is { } value && mapping.TryGetValue(value, out var mapped) ? mapped : id;
        var history = space.State.History.Select(entry => {
            var id = entry.Id;
            if (originalHistory?.Contains(entry.Id) != true)
                while (!historyIds.Add(id)) id = Guid.NewGuid();
            return entry with { Id = id };
        }).ToArray();
        space.State = space.State with {
            Folders = folders.Select(folder => folder with { ParentId = Mapped(folder.ParentId) }).ToArray(),
            Tabs = space.State.Tabs.Select(tab => tab.FolderId == Mapped(tab.FolderId) ? tab
                : Copied(tab, tab with { FolderId = Mapped(tab.FolderId) })).ToArray(),
            History = history
        };
    }

    /// Where each tab's native assets come from, by position. A Start Page in the
    /// archive is left out, as repair drops it.
    private JsonArray Assets(IReadOnlyList<Draft> spaces) {
        var assets = new JsonArray();
        void Add(int space, int position, string section, object record) {
            if (origins.TryGetValue(record, out var origin)) assets.Add((JsonNode)new JsonObject {
                ["spaceIndex"] = space,
                ["tabIndex"] = position,
                ["section"] = section,
                ["sourceIndex"] = origin.Source,
                ["sourceSpaceIndex"] = origin.Space,
                ["sourceTabIndex"] = origin.Tab
            });
        }
        for (int si = 0; si < spaces.Count; si++) {
            var space = spaces[si].State;
            for (int ti = 0; ti < space.Tabs.Count; ti++) Add(si, ti, Key.Tabs, space.Tabs[ti]);
            var archive = space.ArchivedTabs.Where(archived => archived.Tab.Url is not null || archived.Tab.NativeContent is not null).ToArray();
            for (int ti = 0; ti < archive.Length; ti++) Add(si, ti, Key.ArchivedTabs, archive[ti]);
        }
        return assets;
    }

    #endregion
}
