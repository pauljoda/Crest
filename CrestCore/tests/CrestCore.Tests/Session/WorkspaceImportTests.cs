using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Imports into the persistent workspace: what each kind creates, which Space
/// the importing window shows, the identities sync reads as global, where each
/// imported tab came from, what is on disk when an import returns, and the
/// rules that refuse one.
public sealed partial class BrowserContractsTests {
    /// Spaces in the stored format, as an import carries them.
    private static byte[] ImportedSpaces(params JsonNode[] spaces) =>
        Encoding.UTF8.GetBytes(new JsonArray([.. spaces.Select(space => space.DeepClone())]).ToJsonString());

    /// A stored-format Space with its own identities, named `name`, holding `tabs`.
    private static JsonObject ImportedSpace(string name, params JsonObject[] tabs) => new() {
        ["id"] = SwiftId(Guid.NewGuid()),
        ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString().ToUpperInvariant() },
        ["name"] = name,
        ["symbol"] = "globe",
        ["accent"] = "indigo",
        ["tabs"] = new JsonArray([.. tabs]),
        ["folders"] = new JsonArray(),
        ["history"] = new JsonArray(),
        ["archivedTabs"] = new JsonArray()
    };

    /// A stored-format open tab at `url` in `placement`, in `folder` when named.
    private static JsonObject ImportedTab(string url, string placement = "current", Guid? folder = null) {
        var tab = new JsonObject {
            ["id"] = SwiftId(Guid.NewGuid()),
            ["title"] = url,
            ["url"] = url,
            ["placement"] = placement,
            ["lastActivatedAt"] = 800000000.0
        };
        if (placement != "current") tab["savedURL"] = url;
        if (folder is { } id) tab["folderID"] = SwiftId(id);
        return tab;
    }

    private static SpaceCustomization Customization(string name, string symbol = "star") =>
        new(name, symbol, SpaceAccent.Teal, SpaceBrandingPolicy.Normalize(StoredSessionCodec.DecodeBranding(new JsonObject())));

    private static Guid TabId(JsonNode tab) => Guid.Parse(tab["id"]!["rawValue"]!.GetValue<string>());

    [Fact]
    public void AFileImportAddsItsSpacesWholeGivingCollidingRecordsNewIdentities() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var original = device.Authority.Current.Spaces[0];
        // The file holds this session's own Space, as an export of it does.
        var changes = device.Send(new ImportSpaces(device.Workspace, window, ImportedSpaces(session["spaces"]![0]!)));

        var current = device.Authority.Current;
        Assert.Equal((original.Id, original.Tabs[0].Id, original.Folders[0].Id, original.History[0].Id),
            (current.Spaces[0].Id, current.Spaces[0].Tabs[0].Id, current.Spaces[0].Folders[0].Id, current.Spaces[0].History[0].Id));
        var imported = current.Spaces[1];
        Assert.NotEqual(original.Id, imported.Id);
        Assert.NotEqual(original.ProfileId, imported.ProfileId);
        Assert.Equal(original.Settings.Name, imported.Settings.Name);
        // Folder and history identities are global in sync, so the copy takes new ones.
        Assert.NotEqual(original.Folders[0].Id, imported.Folders[0].Id);
        Assert.NotEqual(original.History[0].Id, imported.History[0].Id);
        var tab = Assert.Single(imported.Tabs);
        Assert.NotEqual(original.Tabs[0].Id, tab.Id);
        Assert.Equal(imported.Folders[0].Id, tab.FolderId);
        // The imported tab wears the image of the tab it came from; the file
        // left the session's own tabs as they were.
        Assert.Equal([new ImportedTab(tab.Id, 0, original.Tabs[0].Id)], changes.OfType<TabsImported>().Single().Tabs);
        Assert.DoesNotContain(changes, change => change is TabCopied);
        // A file keeps a first launch's Spaces disposable.
        Assert.NotNull(current.DisposableSeedMarker);
        Assert.Equal((imported.Id, (Guid?)tab.Id), (device.Space(window), device.Tab(window, imported.Id)));
    }

    [Fact]
    public void AReviewedImportJoinsTheSpaceItNamesAndMakesTheRestNewSpaces() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!.AsObject();
        session.Remove("disposableSeedMarker");
        var saved = session["spaces"]![0]!["tabs"]![0]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var folder = Guid.NewGuid();
        // Joins "Reading": its "articles" folder matches the Space's "Articles",
        // and pinned tabs past the limit move to the overflow folder.
        var pinned = Enumerable.Range(0, TabPlacement.PinnedCapacity + 1)
            .Select(index => ImportedTab($"https://pin.example/{index}", "pinned")).ToArray();
        var joining = ImportedSpace("reading",
            [ImportedTab("https://example.com/article#one"), ImportedTab("https://new.example/", "saved", folder), .. pinned]);
        joining["folders"] = new JsonArray(new JsonObject { ["id"] = SwiftId(folder), ["title"] = " articles ", ["location"] = "saved" },
            new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["title"] = "Unused", ["location"] = "saved" });
        var moved = ImportedTab("https://moved.example/");
        var fresh = ImportedSpace("Travel", moved, ImportedTab("https://left.example/"));
        var dropped = ImportedSpace("Dropped", ImportedTab("https://dropped.example/"));
        var joinIds = joining["tabs"]!.AsArray().Skip(1).Select(tab => TabId(tab!)).ToArray();
        SpaceReview[] reviews = [
            new(SpaceId(joining), true, fixture.Space, Customization("Reading"), joinIds, []),
            new(SpaceId(fresh), true, null, Customization("Trips", "airplane"), [TabId(moved)],
                [new(TabId(moved), TabPlacement.Pinned)]),
            new(SpaceId(dropped), false, null, Customization("Dropped"), [], [])
        ];

        var changes = device.Send(new ImportReviewedSpaces(device.Workspace, window, ImportedSpaces(joining, fresh, dropped), reviews));

        var current = device.Authority.Current;
        Assert.Equal(2, current.Spaces.Count);
        var reading = current.Spaces[0];
        Assert.Equal(fixture.Space, reading.Id);
        Assert.Equal(TabId(saved), reading.Tabs[0].Id);
        var overflow = reading.Folders.Single(candidate => candidate.Title == WorkspaceImportPolicy.OverflowFolderTitle);
        Assert.Equal(2, reading.Folders.Count);
        Assert.Equal(reading.Folders[0].Id, reading.Tabs.Single(tab => tab.Url == "https://new.example/").FolderId);
        Assert.Equal(TabPlacement.PinnedCapacity, reading.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        Assert.Equal(overflow.Id, reading.Tabs.Single(tab => tab.Url == $"https://pin.example/{TabPlacement.PinnedCapacity}").FolderId);
        var trips = current.Spaces[1];
        Assert.Equal(("Trips", "airplane"), (trips.Settings.Name, trips.Settings.Symbol));
        var pinnedTrip = Assert.Single(trips.Tabs);
        Assert.Equal((TabId(moved), TabPlacement.Pinned, ManualSetupPolicy.PinnedTabSymbol, "https://moved.example/"),
            (pinnedTrip.Id, pinnedTrip.Placement, pinnedTrip.Symbol, pinnedTrip.SavedUrl));
        Assert.Contains(new ImportedTab(TabId(moved), 1, TabId(moved)), changes.OfType<TabsImported>().Single().Tabs);
        Assert.Equal(reading.Id, device.Space(window));
        Assert.Equal(TabId(moved), device.Tab(window, trips.Id));
    }

    [Fact]
    public void AManualSetupAddsEachDraftsTabsAfterTheirSectionAndTakesTheDraftsOrder() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var existing = device.Authority.Current.Spaces[0];
        var draft = ImportedSpace("ignored", ImportedTab("https://open.example/"), ImportedTab("https://saved.example/", "saved"));
        draft["id"] = SwiftId(existing.Id);
        draft["profile"]!["id"] = existing.ProfileId.ToString();
        var created = ImportedSpace("New", ImportedTab("https://first.example/"), ImportedTab("https://pinned.example/", "pinned"));
        SetupSpace[] drafts = [new(SpaceId(created), true, Customization("Work")), new(existing.Id, false, Customization("Reading"))];

        device.Send(new ApplyManualSetup(device.Workspace, window, ImportedSpaces(draft, created), drafts, OrderWasEdited: true));

        var current = device.Authority.Current;
        Assert.Null(current.DisposableSeedMarker);
        Assert.Equal([SpaceId(created), existing.Id], current.Spaces.Select(space => space.Id));
        Assert.Equal(["https://pinned.example/", "https://first.example/"], current.Spaces[0].Tabs.Select(tab => tab.Url));
        Assert.Equal(["https://example.com/article#one", "https://saved.example/", "https://open.example/"],
            current.Spaces[1].Tabs.Select(tab => tab.Url));
        Assert.Equal("Work", current.Spaces[0].Settings.Name);
        // The window shows the first Space the setup brought, on its last open tab added.
        Assert.Equal(SpaceId(created), device.Space(window));
        Assert.Equal(TabId(created["tabs"]![0]!), device.Tab(window, SpaceId(created)));

        var crowded = ImportedSpace("Crowded", [.. Enumerable.Range(0, TabPlacement.PinnedCapacity + 1)
            .Select(index => ImportedTab($"https://pin.example/{index}", "pinned"))]);
        Assert.Equal(new PinnedTabsFull(TabPlacement.PinnedCapacity), Assert.Throws<Rejected>(() => device.Send(new ApplyManualSetup(
            device.Workspace, window, ImportedSpaces(crowded), [new(SpaceId(crowded), true, Customization("Crowded"))], false))).Rejection);
        var moved = ImportedSpace("Moved");
        moved["id"] = SwiftId(existing.Id);
        Assert.Equal(new SpaceProfileChanged(existing.Id), Assert.Throws<Rejected>(() => device.Send(new ApplyManualSetup(
            device.Workspace, window, ImportedSpaces(moved), [new(existing.Id, false, Customization("Moved"))], false))).Rejection);
        Assert.Equal(new SpaceAlreadyExists(existing.Id), Assert.Throws<Rejected>(() => device.Send(new ApplyManualSetup(
            device.Workspace, window, ImportedSpaces(moved), [new(existing.Id, true, Customization("Moved"))], false))).Rejection);
        var sharing = ImportedSpace("Sharing");
        sharing["profile"]!["id"] = existing.ProfileId.ToString();
        Assert.Equal(new ProfileInUse(existing.ProfileId), Assert.Throws<Rejected>(() => device.Send(new ApplyManualSetup(
            device.Workspace, window, ImportedSpaces(sharing), [new(SpaceId(sharing), true, Customization("Sharing"))], false))).Rejection);
    }

    [Fact]
    public void AnImportIsOnDiskWithItsJournalBeforeItReturnsOrNothingChanges() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        using var app = new CrestApp(new AppConfiguration(directory.Path));
        var answered = app.Send(Adoption(document));
        var (workspace, opened) = TestWorkspaces.OpenStored(app);
        var session = app.Workspace(workspace);
        var sync = app.StoredSync!;
        sync.Flush();
        _ = DrainUntil(app, changes => changes.OfType<SyncJournalChanged>().Any() && changes.OfType<Saved>().Any(), [.. answered, .. opened]);
        var import = new ImportSpaces(workspace, Guid.NewGuid(), ImportedSpaces(ImportedSpace("Imported", ImportedTab("https://imported.example/"))));
        var (stored, staged, kept) = (StoredParts(directory.File), sync.Snapshot, session.Current);

        RefuseWrites(directory.File, "journal");
        Assert.IsType<SaveFailed>(Assert.Throws<Rejected>(() => app.Send(import)).Rejection);
        Assert.Same(kept, session.Current);
        Assert.Same(staged, sync.Snapshot);
        AssertSameParts(stored, StoredParts(directory.File));

        AcceptWrites(directory.File);
        app.Send(import);
        Assert.Equal(2, session.Current.Spaces.Count);
        var parts = StoredParts(directory.File);
        Assert.True(parts["core"].AsSpan().SequenceEqual(session.Checkpoint().Read("core")));
        Assert.True(parts["journal"].AsSpan().SequenceEqual(sync.Snapshot.Read()));
    }

    [Fact]
    public void AnImportIsRefusedWithTheRuleItBreaksAndChangesNothing() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!.AsObject();
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var kept = device.Authority.Current;
        Rejection Refusal(Intent intent) => Assert.Throws<Rejected>(() => device.Send(intent)).Rejection;
        var space = ImportedSpace("Imported", ImportedTab("https://imported.example/"));

        Assert.Equal(new InvalidImport(ImportFlaw.Unreadable), Refusal(new ImportSpaces(device.Workspace, window, "{}"u8.ToArray())));
        var group = SwiftId(Guid.NewGuid());
        var split = ImportedSpace("Split", ImportedTab("https://one.example/"), ImportedTab("https://two.example/", "saved"));
        foreach (var tab in split["tabs"]!.AsArray()) tab!["splitGroupID"] = group.DeepClone();
        Assert.Equal(new InvalidImport(ImportFlaw.MalformedSplit), Refusal(new ImportSpaces(device.Workspace, window, ImportedSpaces(split))));
        Assert.Equal(new SpaceLimitReached(WorkspaceImportPolicy.MaximumSpaces), Refusal(new ImportSpaces(device.Workspace, window,
            ImportedSpaces([.. Enumerable.Range(0, WorkspaceImportPolicy.MaximumSpaces).Select(_ => ImportedSpace("Many"))]))));
        Assert.Equal(new NoIncludedSpaces(), Refusal(new ImportReviewedSpaces(device.Workspace, window, ImportedSpaces(space),
            [new(SpaceId(space), false, null, Customization("Imported"), [], [])])));
        Assert.Equal(new InvalidImport(ImportFlaw.UnpairedChoices), Refusal(new ImportReviewedSpaces(device.Workspace, window,
            ImportedSpaces(space), [new(Guid.NewGuid(), true, null, Customization("Imported"), [], [])])));
        Assert.Equal(new InvalidImport(ImportFlaw.UnpairedChoices), Refusal(new ApplyManualSetup(device.Workspace, window,
            ImportedSpaces(space, space), [new(SpaceId(space), true, Customization("Imported"))], false)));
        var borrowing = device.Borrow(session["spaces"]![0]!);
        Assert.Equal(new PersistentWorkspaceRequired(borrowing), Refusal(new ImportSpaces(borrowing, window, ImportedSpaces(space))));
        Assert.Same(kept, device.Authority.Current);

        var profile = kept.Spaces[0].ProfileId;
        device.Send(new CreateSpace(device.Workspace, window, Guid.NewGuid()));
        device.Send(new BeginDeletingSpace(device.Workspace, window, fixture.Space, Guid.NewGuid()));
        kept = device.Authority.Current;
        var leaving = ImportedSpace("Leaving");
        leaving["id"] = SwiftId(fixture.Space);
        leaving["profile"]!["id"] = profile.ToString();
        Assert.Equal(new SpaceBeingDeleted(fixture.Space), Refusal(new ApplyManualSetup(device.Workspace, window, ImportedSpaces(leaving),
            [new(fixture.Space, false, Customization("Leaving"))], false)));
        Assert.Same(kept, device.Authority.Current);
    }

    [Fact]
    public void TheReviewQueriesAnswerAgainstTheWorkspaceAndThePreviewIsWhatTheImportCommits() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!.AsObject();
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var existing = device.Authority.Current.Spaces[0];
        ImportReviewSpace Reviewed(JsonObject space) => new(SpaceId(space), space["name"]!.GetValue<string>(),
            [.. space["tabs"]!.AsArray().Select(tab => new ImportReviewTab(TabId(tab!), tab!["url"]!.GetValue<string>(),
                TabPlacement.Named(tab["placement"]!.GetValue<string>())!))]);
        var duplicate = ImportedTab("https://example.com/article#one");
        var space = ImportedSpace(" READING ", duplicate, ImportedTab("https://fresh.example/"));

        // Over a first launch's disposable Spaces, everything imports into new Spaces.
        Assert.Null(device.Query(new ImportReviewSuggestions(device.Workspace, [Reviewed(space)])).Spaces.Single().DestinationId);
        // A manual setup that adds nothing still ends the first launch's disposable state.
        device.Send(new ApplyManualSetup(device.Workspace, window, ImportedSpaces(), [], false));
        var suggested = device.Query(new ImportReviewSuggestions(device.Workspace, [Reviewed(space)])).Spaces.Single();
        Assert.Equal((SpaceId(space), (Guid?)existing.Id), (suggested.SourceSpaceId, suggested.DestinationId));
        Assert.Equal([TabId(duplicate)], suggested.DuplicateTabIds);
        Assert.Equal([TabId(space["tabs"]![1]!)], suggested.IncludedTabIds);
        var review = new SpaceReview(SpaceId(space), true, existing.Id, Customization("Reading"), suggested.IncludedTabIds, []);
        var analysis = device.Query(new ImportReviewAnalysis(device.Workspace, [Reviewed(space)], [review]));
        Assert.Equal([TabId(duplicate)], analysis.Spaces.Single().DuplicateTabIds);
        Assert.Equal([existing.Tabs[0].Id], analysis.Spaces.Single().MatchedTabIds);
        Assert.Equal(new InvalidImport(ImportFlaw.UnpairedChoices), Assert.Throws<Rejected>(() =>
            device.Query(new ImportReviewAnalysis(device.Workspace, [Reviewed(space)], []))).Rejection);

        var import = new ImportReviewedSpaces(device.Workspace, window, ImportedSpaces(space), [review]);
        var preview = device.Query(new ImportPreview(import));
        var before = device.Authority.Current;
        Assert.Same(before, device.Authority.Current);
        device.Send(import);
        Assert.Equal(StoredSessionCodec.Encode(preview.Session).ToJsonString(), StoredSessionCodec.Encode(device.Authority.Current).ToJsonString());
        Assert.Equal([TabId(space["tabs"]![1]!)], preview.Imported.Select(tab => tab.SourceTabId));
    }
}
