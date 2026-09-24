using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One import into a session: the Spaces it brings, read from the stored
/// format, and the session's own Spaces while the import edits them. Each
/// import intent runs its own rules over them, then `Finish` gives every
/// record the identity sync needs and says where each tab came from. Image
/// bytes never reach the core: the platform matches each imported tab to the
/// image it holds by the tab it came from.
internal sealed class NativeWorkspaceImport {
    #region Static Variables

    /// How deep an imported Space may nest, as the stored format reads it.
    private static readonly JsonDocumentOptions SpacesDocument = new() { MaxDepth = 64 };

    #endregion

    #region Types

    /// Where a tab or archive record came from: `Source` is the position of
    /// the imported Space among the import's Spaces, or null for the
    /// session's own tab, and `TabId` the identity it had there.
    private sealed record Origin(int? Source, Guid TabId);

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

    /// The session an import leaves, the tabs it placed from its Spaces and the
    /// session's own tabs that took a new identity.
    internal sealed record Result(SessionState Session, IReadOnlyList<ImportedTab> Imported, IReadOnlyList<SessionTabCopy> Copied);

    #endregion

    #region Variables

    private readonly SessionState session;
    /// The session's Spaces, then those the import adds, in the order the
    /// session will hold them.
    private List<Draft> spaces;
    /// The import's Spaces, in the order it brings them.
    private readonly IReadOnlyList<Draft> inputs;
    private readonly Dictionary<Draft, HashSet<Guid>> originalFolderIds;
    private readonly Dictionary<Draft, HashSet<Guid>> originalHistoryIds;
    // Tab and archive records by reference, so two records that share an identity
    // keep their own origins.
    private readonly Dictionary<object, Origin> origins = new(ReferenceEqualityComparer.Instance);
    private Guid? defaultSpace;
    private Guid? seedMarker;
    /// The first Space the import brought or changed, which the window shows.
    private Draft? affected;

    #endregion

    #region Constructors

    /// Reads `spaces`, the imported Spaces in the stored format, against
    /// `session`. Throws `Rejected` with `InvalidImport` for Spaces that do not
    /// decode or hold a split repair would rewrite.
    internal NativeWorkspaceImport(SessionState session, byte[] spaces) {
        this.session = session;
        defaultSpace = session.DefaultSpaceId;
        seedMarker = session.DisposableSeedMarker;
        this.spaces = [.. session.Spaces.Select(space => new Draft(space, isOriginal: true))];
        foreach (var space in this.spaces) Track(space.State, source: null);
        originalFolderIds = this.spaces.ToDictionary(space => space, space => space.State.Folders.Select(f => f.Id).ToHashSet());
        originalHistoryIds = this.spaces.ToDictionary(space => space, space => space.State.History.Select(h => h.Id).ToHashSet());
        inputs = [.. Decoded(spaces).Select(space => new Draft(space, isOriginal: false))];
        for (int index = 0; index < inputs.Count; index++) Track(inputs[index].State, index);
        foreach (var input in inputs)
            WorkspaceImportPolicy.RequireSplitMembership(
                [.. input.State.Tabs.Select(t => new SplitMember(t.SplitGroupId, t.Placement, t.FolderId))]);
    }

    #endregion

    #region Actions - Reading

    /// The imported Spaces, as the stored format spells them in a JSON array.
    private static IReadOnlyList<SpaceState> Decoded(byte[] spaces) {
        try {
            return [.. JsonNode.Parse(spaces, documentOptions: SpacesDocument)!.AsArray().Select(StoredSessionCodec.DecodeSpace)];
        } catch (Exception error) when (StoredSession.IsUndecodable(error)) {
            throw new Rejected(new InvalidImport(ImportFlaw.Unreadable));
        }
    }

    private void Track(SpaceState space, int? source) {
        foreach (var tab in space.Tabs) origins[tab] = new(source, tab.Id);
        foreach (var archived in space.ArchivedTabs) origins[archived] = new(source, archived.Tab.Id);
    }

    /// A changed copy of a tab keeps the tab's origin.
    private TabState Copied(TabState tab, TabState copy) {
        if (origins.TryGetValue(tab, out var origin)) origins[copy] = origin;
        return copy;
    }

    /// Each choice with the imported Space it names, in the choices' order.
    /// Throws `Rejected` with `InvalidImport` unless they name each imported
    /// Space exactly once.
    private IReadOnlyList<(Draft Input, TChoice Choice)> Pair<TChoice>(IReadOnlyList<TChoice> choices, Func<TChoice, Guid> named) {
        var paired = ImportReviewPolicy.Paired(inputs, choices, input => input.Id, named);
        var byChoice = paired.ToDictionary(pair => named(pair.Choice), pair => pair.Source);
        return [.. choices.Select(choice => (byChoice[named(choice)], choice))];
    }

    #endregion

    #region Actions - Imports

    /// A file's Spaces join after the session's own, each showing its first
    /// tab. Throws `Rejected` with `SpaceLimitReached` when they do not fit.
    internal void AddSpaces() {
        WorkspaceImportPolicy.RequireSpaceCapacity(spaces.Count, inputs.Count);
        foreach (var input in inputs) {
            if (input.State.Tabs.FirstOrDefault() is { } first) input.ShownTab = first.Id;
            spaces.Add(input);
        }
        affected = inputs.FirstOrDefault();
    }

    /// Applies a manual setup's drafts in their order; see `ApplyManualSetup`.
    internal void ApplyDrafts(IReadOnlyList<SetupSpace> drafts, bool orderWasEdited) {
        var paired = Pair(drafts, draft => draft.SpaceId);
        WorkspaceImportPolicy.RequireSpaceCapacity(spaces.Count, drafts.Count(draft => draft.IsNew));
        foreach (var (input, draft) in paired) {
            var id = input.Id;
            bool created = draft.IsNew;
            var destination = created ? input : spaces.FirstOrDefault(s => s.Id == id);
            if (destination is null) continue; // A draft cannot recreate an existing Space deleted elsewhere.
            Available(id);
            if (!created && destination.State.ProfileId != input.State.ProfileId) throw new Rejected(new SpaceProfileChanged(id));
            if (created && spaces.Any(s => s.Id == id)) throw new Rejected(new SpaceAlreadyExists(id));
            if (created && spaces.Any(s => s.State.ProfileId == input.State.ProfileId))
                throw new Rejected(new ProfileInUse(input.State.ProfileId));
            Customize(destination, draft.Customization);
            var added = input.State.Tabs.ToArray();
            var old = created ? [] : destination.State.Tabs.ToArray();
            WorkspaceImportPolicy.RequirePinnedCapacity(old.Concat(added).Count(t => t.Placement == TabPlacement.Pinned));
            var ordered = added.OrderBy(t => t.Placement.Rank).ToArray();
            if (created) destination.State = destination.State with { Tabs = ordered };
            else {
                var list = old.ToList();
                // Each section's imported tabs follow the tabs it already holds.
                foreach (var placement in TabPlacement.All) {
                    int end = list.FindIndex(t => t.Placement.Rank > placement.Rank);
                    list.InsertRange(end < 0 ? list.Count : end, ordered.Where(t => t.Placement == placement));
                }
                destination.State = destination.State with { Tabs = list.ToArray() };
            }
            ShowAdded(destination, created ? added : ordered);
            if (created) spaces.Add(destination);
            if (created || added.Length > 0) affected ??= destination;
        }
        if (orderWasEdited) {
            var order = paired.Select(pair => pair.Input.Id).ToArray();
            spaces = [.. order.Select(id => spaces.FirstOrDefault(s => s.Id == id)).OfType<Draft>()
                .Concat(spaces.Where(s => !order.Contains(s.Id)))];
        }
        seedMarker = null;
    }

    /// Imports the reviewed Spaces the reviews include, in their order; see
    /// `ImportReviewedSpaces`. New identities come from `ids`.
    internal void ImportReviewed(IReadOnlyList<SpaceReview> reviews, IIdSource ids) {
        var included = Pair(reviews, review => review.SourceSpaceId).Where(pair => pair.Choice.Included).ToArray();
        if (included.Length == 0) throw new Rejected(new NoIncludedSpaces());
        bool replaceSeed = seedMarker is not null;
        WorkspaceImportPolicy.RequireSpaceCapacity(replaceSeed ? 0 : spaces.Count,
            included.Count(pair => pair.Choice.DestinationId is null));
        if (replaceSeed) {
            if (session.SpaceDeletions.Count > 0) throw new Rejected(new SpaceBeingDeleted(session.SpaceDeletions[0].SpaceId));
            spaces.Clear(); defaultSpace = null;
        }
        foreach (var (input, review) in included) {
            var destination = review.DestinationId is { } destinationId ? spaces.FirstOrDefault(s => s.Id == destinationId) : input;
            if (destination is null) continue;
            Available(destination.Id);
            Customize(destination, review.Customization);
            Import(review, input, destination, isNew: review.DestinationId is null, ids);
            if (review.DestinationId is null) spaces.Add(destination);
            affected ??= destination;
        }
        if (affected is not null) seedMarker = null;
    }

    #endregion

    #region Actions - Reviewed tabs

    /// A reviewed Space's included tabs, in the placements the review chose, with
    /// the saved folders they need. Pinned tabs past the limit become saved tabs
    /// in the overflow folder. New identities come from `ids`.
    private void Import(SpaceReview review, Draft input, Draft destination, bool isNew, IIdSource ids) {
        var included = review.IncludedTabIds.ToHashSet();
        var overrides = review.Placements.GroupBy(choice => choice.TabId).ToDictionary(group => group.Key, group => group.Last().Placement);
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
            while (folders.Any(f => f.Id == identity)) identity = ids.Next();
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
            if (placement == TabPlacement.Pinned && !placement.Holds(++pinned)) {
                placement = TabPlacement.Saved;
                if (overflowFolder is null && folders.Count < WorkspaceImportPolicy.MaximumFolders) {
                    overflowFolder = new FolderState(ids.Next(), TabPlacement.Saved, WorkspaceImportPolicy.OverflowFolderTitle,
                        WorkspaceImportPolicy.OverflowFolderSymbol);
                    folders.Add(overflowFolder);
                }
                folder = overflowFolder?.Id;
            } else folder = placement == TabPlacement.Saved && tab.FolderId is { } old && mapping.TryGetValue(old, out var copied)
                  ? copied : null;
            return Copied(tab, tab with {
                Placement = placement,
                FolderId = folder,
                SavedUrl = placement.IsDurable ? tab.SavedUrl ?? tab.Url : null,
                Symbol = placement == TabPlacement.Pinned ? ManualSetupPolicy.PinnedTabSymbol : tab.Symbol
            });
        }).ToArray();
        var existing = isNew ? [] : destination.State.Tabs;
        destination.State = destination.State with { Folders = folders.ToArray(), Tabs = [.. existing, .. edited] };
        // A new Space shows its first imported tab.
        if (isNew && edited.FirstOrDefault() is { } first) destination.ShownTab = first.Id;
    }

    #endregion

    #region Actions - Identities

    /// The session the import leaves, stamped `now`: every folder and history
    /// record keeps an identity no other Space holds, repair gives each Space,
    /// profile and tab its own, and `followUp` shows the first Space the import
    /// brought or changed and the tab each Space it touched shows first. New
    /// identities come from `ids`, in the order the records are met.
    internal Result Finish(DateTimeOffset now, IIdSource ids, WindowFollowUp followUp) {
        // Folder and history record IDs are global in sync, even though their
        // native collections are nested under Spaces. Reserve existing IDs first
        // so an imported Space placed earlier cannot steal another Space's records.
        var folderIds = originalFolderIds.Values.SelectMany(set => set).ToHashSet();
        var historyIds = originalHistoryIds.Values.SelectMany(set => set).ToHashSet();
        foreach (var space in spaces) Reserve(space, space.IsOriginal ? originalFolderIds[space] : null,
            space.IsOriginal ? originalHistoryIds[space] : null, folderIds, historyIds, ids);
        int affectedIndex = affected is null ? -1 : spaces.IndexOf(affected);
        // Repair may replace colliding identities, so hints and origins travel by position.
        var shown = new List<(int Space, int Tab)>();
        for (int si = 0; si < spaces.Count; si++)
            if (spaces[si].ShownTab is { } tab && spaces[si].State.Tabs.Select(t => t.Id).ToList().IndexOf(tab) is var ti and >= 0)
                shown.Add((si, ti));
        var before = spaces.Select(space => space.State).ToArray();
        var imported = session with {
            Spaces = before,
            DefaultSpaceId = defaultSpace,
            DisposableSeedMarker = seedMarker
        };
        var repaired = NativeSessionMaintenance.Repair(imported, now, null, ids, out _);
        // Show the imported instance even when repair replaced a colliding ID.
        if (affectedIndex >= 0) followUp.ShowSpace(repaired.Spaces[affectedIndex].Id);
        foreach (var (si, ti) in shown) followUp.ShowTab(repaired.Spaces[si].Id, repaired.Spaces[si].Tabs[ti].Id);
        var (importedTabs, copies) = Placed(before, repaired);
        return new(repaired, importedTabs, copies);
    }

    /// Where each tab of `repaired` came from, matched by position with the
    /// records `before` held: each tab an imported Space brought, and each of
    /// the session's own tabs repair gave a new identity. A Space repair kept
    /// as it was, such as one being deleted, placed nothing.
    private (IReadOnlyList<ImportedTab> Imported, IReadOnlyList<SessionTabCopy> Copied) Placed(IReadOnlyList<SpaceState> before,
        SessionState repaired) {
        var imported = new List<ImportedTab>();
        var copied = new List<SessionTabCopy>();
        void Place(object record, Guid id) {
            if (!origins.TryGetValue(record, out var origin)) return;
            if (origin.Source is { } source) imported.Add(new(id, source, origin.TabId));
            else if (id != origin.TabId) copied.Add(new(origin.TabId, id));
        }
        for (int si = 0; si < before.Count; si++) {
            var space = repaired.Spaces[si];
            if (ReferenceEquals(space, before[si])) continue;
            for (int ti = 0; ti < before[si].Tabs.Count; ti++) Place(before[si].Tabs[ti], space.Tabs[ti].Id);
            // Repair drops a Start Page from the archive.
            var archive = before[si].ArchivedTabs
                .Where(archived => archived.Tab.Url is not null || archived.Tab.NativeContent is not null).ToArray();
            for (int ti = 0; ti < archive.Length; ti++) Place(archive[ti], space.ArchivedTabs[ti].Tab.Id);
        }
        return (imported, copied);
    }

    /// Gives a Space's folders and history identities no other Space holds,
    /// keeping the ones it had before the import, and points its folder
    /// references at the new folder identities.
    private void Reserve(Draft space, HashSet<Guid>? originalFolders, HashSet<Guid>? originalHistory,
        HashSet<Guid> folderIds, HashSet<Guid> historyIds, IIdSource ids) {
        Dictionary<Guid, Guid> mapping = [];
        var folders = space.State.Folders.Select(folder => {
            var id = folder.Id;
            if (originalFolders?.Contains(folder.Id) != true)
                while (!folderIds.Add(id)) id = ids.Next();
            mapping.TryAdd(folder.Id, id);
            return folder with { Id = id };
        }).ToArray();
        Guid? Mapped(Guid? id) => id is { } value && mapping.TryGetValue(value, out var mapped) ? mapped : id;
        var history = space.State.History.Select(entry => {
            var id = entry.Id;
            if (originalHistory?.Contains(entry.Id) != true)
                while (!historyIds.Add(id)) id = ids.Next();
            return entry with { Id = id };
        }).ToArray();
        space.State = space.State with {
            Folders = folders.Select(folder => folder with { ParentId = Mapped(folder.ParentId) }).ToArray(),
            Tabs = space.State.Tabs.Select(tab => tab.FolderId == Mapped(tab.FolderId) ? tab
                : Copied(tab, tab with { FolderId = Mapped(tab.FolderId) })).ToArray(),
            History = history
        };
    }

    #endregion

    #region Actions - Rules

    private static void Customize(Draft space, SpaceCustomization customization) => space.State = space.State with {
        Settings = space.State.Settings with {
            Name = SpaceOrganizationPolicy.Name(customization.Name),
            Symbol = SpaceOrganizationPolicy.Symbol(customization.Symbol),
            Accent = customization.Accent,
            Branding = SpaceBrandingPolicy.Normalize(customization.Branding)
        }
    };

    /// Throws `Rejected` with `SpaceBeingDeleted` when `id` is going away.
    private void Available(Guid id) {
        if (session.SpaceDeletions.Any(deletion => deletion.SpaceId == id)) throw new Rejected(new SpaceBeingDeleted(id));
    }

    private static void ShowAdded(Draft space, IEnumerable<TabState> tabs) {
        var chosen = tabs.LastOrDefault(t => t.Placement == TabPlacement.Current) ?? tabs.FirstOrDefault();
        if (chosen is not null) space.ShownTab = chosen.Id;
    }

    #endregion
}
