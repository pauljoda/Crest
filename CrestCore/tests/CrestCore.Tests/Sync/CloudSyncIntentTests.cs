using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Static Variables

    /// The device that wrote the records a test receives from the cloud.
    private static readonly Guid CloudDevice = Guid.Parse("C10D0000-0000-4000-8000-000000000001");

    #endregion

    #region Actions - Tests

    [Fact]
    public void AMergeIsOnDiskWithItsJournalBeforeItReturnsAndPublishesBothInTheNextDrain() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var tab = Guid.NewGuid();

        var answer = stored.App.Send(new MergeSyncRecords([CloudTab(tab, fixture.Space, clock: 5)]));
        var drained = stored.App.Drain();

        Assert.Empty(answer);
        Assert.Contains(stored.Session.Current.Spaces.Single().Tabs, held => held.Id == tab);
        Assert.Contains(drained, change => change is TabsChanged changed && changed.Updated.Any(updated => updated.Id == tab));
        Assert.IsType<SyncJournalChanged>(drained[^1]);
        var parts = StoredParts(directory.File);
        Assert.True(parts["core"].AsSpan().SequenceEqual(stored.Session.Checkpoint().Read("core")));
        Assert.True(parts["journal"].AsSpan().SequenceEqual(stored.Sync.Snapshot.Read()));
        Assert.Contains(JsonNode.Parse(parts["journal"])!["records"]!.AsArray(),
            record => record!["id"]!["value"]!.GetValue<string>() == tab.ToString("D").ToUpperInvariant());
    }

    [Fact]
    public void AMergeWhoseSaveFailsChangesNeitherTheSessionNorTheJournalNorTheFile() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var (session, journal, parts) = (stored.Session.Current, stored.Sync.Snapshot, StoredParts(directory.File));
        RefuseWrites(directory.File, "journal");

        var refused = Assert.Throws<Rejected>(() => stored.App.Send(new MergeSyncRecords([CloudTab(Guid.NewGuid(), fixture.Space, clock: 5)])));

        Assert.IsType<SaveFailed>(refused.Rejection);
        Assert.Same(session, stored.Session.Current);
        Assert.Same(journal, stored.Sync.Snapshot);
        AssertSameParts(parts, StoredParts(directory.File));
    }

    /// Records the cloud may send that no rule lets the core take, each
    /// refused by the rule it breaks, never by the net for failures no rule
    /// names, and never as a fault.
    [Fact]
    public void HostileCloudRecordsAreRefusedByTheRuleTheyBreakAndChangeNothing() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var held = fixture.Tab;
        var elsewhere = Guid.NewGuid();
        var profile = Guid.NewGuid();
        var folder = Guid.NewGuid();
        var otherFolder = Guid.NewGuid();
        JsonObject Body(SyncRecord record) => JsonNode.Parse(record.Body)!.AsObject();
        SyncRecord With(SyncRecord record, Action<JsonObject> edit) {
            var body = Body(record);
            edit(body);
            return record with { Body = Bytes(body) };
        }
        var cases = new Dictionary<string, (IReadOnlyList<SyncRecord> Records, Rejection Expected)> {
            ["a body that is no JSON"] = ([CloudTab(Guid.NewGuid(), fixture.Space, 5) with { Body = "not json"u8.ToArray() }],
                Invalid(SyncRecordFlaw.MalformedRecord)),
            ["a body that is no object"] = ([CloudTab(Guid.NewGuid(), fixture.Space, 5) with { Body = "[1,2]"u8.ToArray() }],
                Invalid(SyncRecordFlaw.MalformedRecord)),
            ["a payload of another kind"] = ([With(CloudTab(Guid.NewGuid(), fixture.Space, 5), body => body["type"] = "folder")],
                Invalid(SyncRecordFlaw.IdentityMismatch)),
            ["a payload naming another tab"] = ([With(CloudTab(Guid.NewGuid(), fixture.Space, 5),
                body => body["value"]!["id"] = SwiftId(Guid.NewGuid()))], Invalid(SyncRecordFlaw.IdentityMismatch)),
            ["a payload with no identity"] = ([With(CloudTab(Guid.NewGuid(), fixture.Space, 5),
                body => body["value"]!.AsObject().Remove("id"))], Invalid(SyncRecordFlaw.MalformedRecord)),
            ["a Space record naming another Space"] = ([CloudSpace(Guid.NewGuid(), profile, 5) with { SpaceId = Guid.NewGuid() }],
                Invalid(SyncRecordFlaw.IdentityMismatch)),
            ["an empty identity"] = ([CloudTab(Guid.NewGuid(), fixture.Space, 5) with { Id = Guid.Empty }],
                Invalid(SyncRecordFlaw.MalformedRecord)),
            ["a tombstone for no known reason"] = ([Tombstone(SyncRecordKind.Tab, Guid.NewGuid(), fixture.Space, 5, reason: "forgotten")],
                Invalid(SyncRecordFlaw.MalformedRecord)),
            ["a tombstone deleted at no date"] = ([Tombstone(SyncRecordKind.Tab, Guid.NewGuid(), fixture.Space, 5, deletedAt: "soon")],
                Invalid(SyncRecordFlaw.MalformedRecord)),
            ["a placement no build knows"] = ([With(CloudTab(Guid.NewGuid(), fixture.Space, 5), body => body["value"]!["placement"] = "sideways")],
                Invalid(SyncRecordFlaw.MalformedRecord)),
            ["two records with one identity"] = ([CloudTab(elsewhere, fixture.Space, 5), CloudTab(elsewhere, fixture.Space, 6)],
                Invalid(SyncRecordFlaw.DuplicateRecord)),
            ["a record the journal holds in another Space"] = ([CloudTab(held, Guid.NewGuid(), 5)], Invalid(SyncRecordFlaw.ChangedSpace)),
            ["two Spaces with one profile"] = ([CloudSpace(Guid.NewGuid(), profile, 5), CloudSpace(Guid.NewGuid(), profile, 5)],
                Invalid(SyncRecordFlaw.SharedProfile)),
            ["a Space under another profile"] = ([CloudSpace(fixture.Space, Guid.NewGuid(), ulong.MaxValue / 2)],
                Invalid(SyncRecordFlaw.ProfileChanged)),
            ["more pinned tabs than a Space holds"] = ([.. Enumerable.Range(0, TabPlacement.PinnedCapacity + 1).Select(index =>
                With(CloudTab(Guid.NewGuid(), fixture.Space, 5), body => body["value"]!["placement"] = TabPlacement.Pinned.Name))],
                Invalid(SyncRecordFlaw.TooManyPinnedTabs)),
            ["folders inside each other"] = ([CloudFolder(folder, fixture.Space, parent: otherFolder, 5),
                CloudFolder(otherFolder, fixture.Space, parent: folder, 5)], Invalid(SyncRecordFlaw.InvalidFolderHierarchy)),
            ["a tab in another Space's folder"] = ([CloudSpace(elsewhere, profile, 5), CloudFolder(folder, elsewhere, parent: null, 5),
                With(CloudTab(Guid.NewGuid(), fixture.Space, 5), body => {
                    body["value"]!["placement"] = TabPlacement.Saved.Name;
                    body["value"]!["folderID"] = SwiftId(folder);
                })], Invalid(SyncRecordFlaw.DanglingFolder)),
            ["a clock no later version can follow"] = ([CloudTab(Guid.NewGuid(), fixture.Space, ulong.MaxValue)],
                new SyncStagingRefused(SyncStagingFailure.ClockExhausted)),
        };
        foreach (var (name, (records, expected)) in cases) {
            var (session, journal, parts) = (stored.Session.Current, stored.Sync.Snapshot, StoredParts(directory.File));

            var refused = Assert.Throws<Rejected>(() => stored.App.Send(new MergeSyncRecords(records)));

            Assert.True(Same(expected, refused.Rejection), $"{name}: {refused.Rejection}");
            Assert.Same(session, stored.Session.Current);
            Assert.Same(journal, stored.Sync.Snapshot);
            AssertSameParts(parts, StoredParts(directory.File));
        }
    }

    [Fact]
    public void ASeedTakesTheCloudOnceAndIsLeftAloneAfterwards() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        Assert.NotNull(fixture.Document["session"]!["disposableSeedMarker"]);
        using var stored = StoredSyncing(directory, fixture.Document, keepsSeed: true);
        var cloud = Guid.NewGuid();

        stored.App.Send(new ReplaceSeedWithCloudRecords([CloudSpace(cloud, Guid.NewGuid(), 5), CloudTab(Guid.NewGuid(), cloud, 5)]));
        var replaced = stored.Session.Current;
        stored.App.Send(new ReplaceSeedWithCloudRecords([CloudSpace(Guid.NewGuid(), Guid.NewGuid(), 6)]));

        Assert.Null(replaced.DisposableSeedMarker);
        Assert.Equal(cloud, Assert.Single(replaced.Spaces).Id);
        Assert.Same(replaced, stored.Session.Current);
    }

    [Fact]
    public void AMergeThatDeletesABorrowedSpaceClosesItsBorrower() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var borrower = TestWorkspaces.Borrow(stored.App, stored.Workspace, fixture.Document["session"]!["spaces"]![0]!);

        stored.App.Send(new MergeSyncRecords([Tombstone(SyncRecordKind.Space, fixture.Space, fixture.Space, ulong.MaxValue / 2)]));

        Assert.Contains(stored.App.Drain(), change => change is WorkspaceClosed closed && closed.WorkspaceId == borrower);
        Assert.Contains(stored.Session.Current.SpaceDeletions, deletion => deletion.SpaceId == fixture.Space);
    }

    /// A merge that lands before the stage of a folder's deletion runs still
    /// deletes the folder's record as the person did, so the folder stays
    /// deleted on every device.
    [Fact]
    public void AMergeKeepsTheReasonOfADeletionItStagesInsteadOfItsQueuedStage() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var folder = SpaceId(fixture.Document["session"]!["spaces"]![0]!["folders"]![0]!);

        stored.App.Send(new DeleteFolder(stored.Workspace, fixture.Space, folder));
        stored.App.Send(new MergeSyncRecords([CloudTab(Guid.NewGuid(), fixture.Space, clock: 5)]));

        Assert.Equal("explicitDelete", FolderTombstoneReason(stored.Sync, folder));
        Assert.DoesNotContain(stored.Session.Current.Spaces.Single().Folders, held => held.Id == folder);
    }

    /// An overwrite that lands before the stage of a folder's deletion runs
    /// deletes the folder's record as the person did, so the overwrite that
    /// reaches every device keeps it deleted there too.
    [Fact]
    public void AnOverwriteKeepsTheReasonOfADeletionItStagesInsteadOfItsQueuedStage() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var folder = SpaceId(fixture.Document["session"]!["spaces"]![0]!["folders"]![0]!);

        stored.App.Send(new DeleteFolder(stored.Workspace, fixture.Space, folder));
        stored.App.Send(new OverwriteCloud([CloudTab(Guid.NewGuid(), fixture.Space, clock: 5)]));

        Assert.Equal("explicitDelete", FolderTombstoneReason(stored.Sync, folder));
    }

    /// A merge the core refuses leaves the stage it superseded to run as it
    /// would have.
    [Fact]
    public void ARefusedMergeQueuesTheStageItSupersededAgain() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var folder = SpaceId(fixture.Document["session"]!["spaces"]![0]!["folders"]![0]!);

        stored.App.Send(new DeleteFolder(stored.Workspace, fixture.Space, folder));
        Assert.Throws<Rejected>(() => stored.App.Send(new MergeSyncRecords([CloudTab(fixture.Tab, Guid.NewGuid(), clock: 5)])));
        stored.Sync.Flush();

        Assert.Equal("explicitDelete", FolderTombstoneReason(stored.Sync, folder));
    }

    /// The cloud saved one record at the version the journal holds and
    /// another at an older one: only the first stops waiting to upload, and
    /// the journal is on disk before the acknowledgement returns.
    [Fact]
    public void AnAcknowledgementClearsOnlyTheVersionsTheCloudSaved() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var pending = stored.App.Query(new PendingUploads()).Records;
        var records = stored.App.Query(new RecordsToUpload(pending)).Records;
        var (saved, stale) = (records[0], records[1]);
        stored.App.Drain();

        var answer = stored.App.Send(new AcknowledgeUploads([
            new(new(saved.Kind, saved.Id), saved.Version),
            new(new(stale.Kind, stale.Id), stale.Version with { Clock = stale.Version.Clock - 1 })
        ]));

        Assert.Empty(answer);
        var waiting = stored.App.Query(new PendingUploads()).Records;
        Assert.Equal([.. pending.Where(reference => reference != new SyncRecordReference(saved.Kind, saved.Id))], waiting);
        Assert.Equal(pending.Count - 1, stored.App.Drain().OfType<SyncJournalChanged>().Single().PendingRecords);
        Assert.True(StoredParts(directory.File)["journal"].AsSpan().SequenceEqual(stored.Sync.Snapshot.Read()));
    }

    /// A fetch that brings an older version of a record the cloud already
    /// acknowledged does not make it wait to upload again.
    [Fact]
    public void AnOlderFetchedVersionDoesNotQueueAnAcknowledgedRecordAgain() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var tab = new SyncRecordReference(SyncRecordKind.Tab, fixture.Tab);
        var local = Assert.Single(stored.App.Query(new RecordsToUpload([tab])).Records);
        stored.App.Send(new AcknowledgeUploads([new(tab, local.Version)]));
        var older = JsonNode.Parse(local.Body)!.AsObject();
        older["value"]!["title"] = "An older title";

        stored.App.Send(new MergeSyncRecords([local with {
            Version = new(local.Version.Clock - 1, CloudDevice), Body = Bytes(older)
        }]));

        Assert.DoesNotContain(tab, stored.App.Query(new PendingUploads()).Records);
        var kept = Assert.Single(stored.App.Query(new RecordsToUpload([tab])).Records);
        Assert.Equal(local.Version, kept.Version);
        Assert.True(kept.Body.AsSpan().SequenceEqual(local.Body));
    }

    [Fact]
    public void RecordsToUploadNamesTheRecordsTheJournalNoLongerHoldsAsGone() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var tab = new SyncRecordReference(SyncRecordKind.Tab, fixture.Tab);
        var space = new SyncRecordReference(SyncRecordKind.Space, fixture.Space);
        var unknown = new SyncRecordReference(SyncRecordKind.Tab, Guid.NewGuid());
        var archived = new SyncRecordReference(SyncRecordKind.Archive, fixture.Tab);

        var batch = stored.App.Query(new RecordsToUpload([tab, unknown, space, archived]));

        Assert.Equal([tab, space], batch.Records.Select(record => new SyncRecordReference(record.Kind, record.Id)));
        Assert.Equal([unknown, archived], batch.Gone);
        Assert.All(batch.Records, record => Assert.False(record.IsTombstone));
        Assert.Equal(fixture.Space, batch.Records[0].SpaceId);
    }

    /// The cloud holds the same content when it holds the same records, each
    /// in its Space with an equivalent payload or tombstone, whatever versions
    /// wrote them.
    [Fact]
    public void ACloudComparisonMatchesTheSameContentWhateverItsVersionsAndCountsBothSides() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var device = stored.App.Query(new RecordsToUpload(stored.App.Query(new PendingUploads()).Records)).Records;
        var cloud = device.Select(record => record with { Version = new(record.Version.Clock + 7, CloudDevice) }).ToList();
        int tab = cloud.FindIndex(record => record.Kind == SyncRecordKind.Tab);
        var retitled = JsonNode.Parse(cloud[tab].Body)!.AsObject();
        retitled["value"]!["title"] = "Another title";

        var same = stored.App.Query(new CloudComparison(cloud));
        var edited = stored.App.Query(new CloudComparison([.. cloud.Select((record, index) =>
            index == tab ? record with { Body = Bytes(retitled) } : record)]));
        var deleted = stored.App.Query(new CloudComparison([.. cloud.Select((record, index) =>
            index == tab ? Tombstone(record.Kind, record.Id, record.SpaceId, record.Version.Clock) : record)]));
        var missing = stored.App.Query(new CloudComparison([.. cloud.Where((_, index) => index != tab)]));

        Assert.Equal(new CloudContentComparison(true, device.Count, device.Count, 1, 1), same);
        Assert.False(edited.Matches);
        Assert.False(deleted.Matches);
        Assert.Equal(new CloudContentComparison(false, device.Count, device.Count - 1, 1, 1), missing);
    }

    /// An overwrite leaves every record waiting to upload over the cloud's; a
    /// replacement leaves none.
    [Fact]
    public void AnOverwriteLeavesEveryRecordWaitingAndAReplacementNone() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        using var stored = StoredSyncing(directory, fixture.Document);
        var cloud = Guid.NewGuid();
        var records = new[] { CloudSpace(cloud, Guid.NewGuid(), 5), CloudTab(Guid.NewGuid(), cloud, 6) };
        stored.App.Send(new AcknowledgeUploads([.. stored.App.Query(new RecordsToUpload(stored.App.Query(new PendingUploads()).Records))
            .Records.Select(record => new UploadedRecord(new(record.Kind, record.Id), record.Version))]));
        Assert.Empty(stored.App.Query(new PendingUploads()).Records);
        stored.App.Drain();

        stored.App.Send(new OverwriteCloud(records));
        var overwritten = stored.App.Drain().OfType<SyncJournalChanged>().Single();
        Assert.Equal(overwritten.Records, stored.App.Query(new PendingUploads()).Records.Count);
        Assert.Equal(overwritten.Records, overwritten.PendingRecords);

        stored.App.Send(new ReplaceWithCloudRecords(records));
        Assert.Empty(stored.App.Query(new PendingUploads()).Records);
        Assert.Equal(0, stored.App.Drain().OfType<SyncJournalChanged>().Last().PendingRecords);
    }

    /// A first launch's disposable seed uploads nothing, even when the journal
    /// it carried holds records waiting to upload.
    [Fact]
    public void ADisposableSeedUploadsNothingOfTheJournalItCarried() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var carried = SyncTabRecord(Guid.NewGuid(), fixture.Space, 9, Guid.NewGuid());
        using var stored = StoredSyncing(directory, fixture.Document, keepsSeed: true, journal: JournalDocument(carried));
        var reference = new SyncRecordReference(SyncRecordKind.Tab, Guid.Parse(carried["id"]!["value"]!.GetValue<string>()));

        Assert.Empty(stored.App.Query(new PendingUploads()).Records);
        Assert.Equal([reference], stored.App.Query(new RecordsToUpload([reference])).Gone);
        Assert.Equal(new CloudContentComparison(true, 0, 0, 0, 0), stored.App.Query(new CloudComparison([])));
        stored.App.Drain();
        stored.App.Send(new AcknowledgeUploads([]));
        Assert.Equal(0, stored.App.Drain().OfType<SyncJournalChanged>().Single().PendingRecords);
    }

    /// The transport's calls are refused while the file holds no session, not
    /// read as an empty journal.
    [Fact]
    public void TheTransportIsRefusedWhileTheFileHoldsNoSession() {
        using var directory = new StorageDirectory();
        using var app = new CrestApp(new AppConfiguration(directory.Path));

        Assert.IsType<NoStoredSession>(Assert.Throws<Rejected>(() => app.Query(new PendingUploads())).Rejection);
        Assert.IsType<NoStoredSession>(Assert.Throws<Rejected>(() => app.Query(new CloudComparison([]))).Rejection);
        Assert.IsType<NoStoredSession>(Assert.Throws<Rejected>(() => app.Send(new AcknowledgeUploads([]))).Rejection);
        app.SettleSync();
    }

    #endregion

    #region Actions - Fixtures

    /// Why the journal `sync` holds deletes `folder`'s record, or null while it
    /// holds no tombstone for it.
    private static string? FolderTombstoneReason(NativeSyncAuthority sync, Guid folder) =>
        JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray()
            .Single(record => record!["id"]!["kind"]!.GetValue<string>() == "folder"
                && Guid.Parse(record["id"]!["value"]!.GetValue<string>()) == folder)!["tombstone"]?["reason"]?.GetValue<string>();

    /// A core keeping `document` in its file, with `journal` when there is one
    /// and without its seed marker unless it `keepsSeed`, opened as a launch
    /// opens it once its launch stage settled.
    private sealed record StoredSync(CrestApp App, Guid Workspace, NativeSessionAuthority Session, NativeSyncAuthority Sync)
        : IDisposable {
        public void Dispose() => App.Dispose();
    }

    private static StoredSync StoredSyncing(StorageDirectory directory, JsonObject document, bool keepsSeed = false,
        JsonObject? journal = null) {
        var session = document["session"]!.AsObject();
        if (!keepsSeed) session.Remove("disposableSeedMarker");
        var app = new CrestApp(new AppConfiguration(directory.Path));
        var answered = app.Send(Adoption(session, journal));
        var (workspace, opened) = TestWorkspaces.OpenStored(app);
        var sync = app.StoredSync!;
        sync.Flush();
        _ = DrainUntil(app, changes => changes.OfType<Saved>().Any(), [.. answered, .. opened]);
        return new(app, workspace, app.Workspace(workspace), sync);
    }

    private static InvalidSyncRecords Invalid(SyncRecordFlaw flaw) => new(flaw, null);

    /// Whether `actual` is the rejection `expected` names, whatever subject it
    /// names.
    private static bool Same(Rejection expected, Rejection actual) => (expected, actual) switch {
        (InvalidSyncRecords wanted, InvalidSyncRecords refused) => wanted.Flaw == refused.Flaw,
        _ => expected == actual
    };

    private static SyncRecord CloudTab(Guid id, Guid space, ulong clock) => new(SyncRecordKind.Tab, id, space,
        new SyncVersion(clock, CloudDevice), Bytes(new JsonObject {
            ["type"] = "tab",
            ["value"] = new JsonObject {
                ["id"] = SwiftId(id),
                ["spaceID"] = SwiftId(space),
                ["title"] = "From the cloud",
                ["url"] = "https://cloud.example/" + id.ToString("N"),
                ["symbol"] = "globe",
                ["placement"] = "current",
                ["lastActivatedAt"] = 800000050.0,
                ["orderToken"] = "8000000000000000"
            }
        }), IsTombstone: false);

    private static SyncRecord CloudSpace(Guid id, Guid profile, ulong clock) => new(SyncRecordKind.Space, id, id,
        new SyncVersion(clock, CloudDevice), Bytes(new JsonObject {
            ["type"] = "space",
            ["value"] = new JsonObject {
                ["id"] = SwiftId(id),
                ["profileID"] = profile.ToString("D").ToUpperInvariant(),
                ["name"] = "From the cloud",
                ["symbol"] = "cloud",
                ["accent"] = "teal",
                ["orderToken"] = "8000000000000000",
                ["splitGroups"] = new JsonArray()
            }
        }), IsTombstone: false);

    private static SyncRecord CloudFolder(Guid id, Guid space, Guid? parent, ulong clock) {
        var value = new JsonObject {
            ["id"] = SwiftId(id),
            ["spaceID"] = SwiftId(space),
            ["title"] = "Cloud folder",
            ["location"] = "saved",
            ["orderToken"] = "8000000000000000"
        };
        if (parent is { } folder) value["parentID"] = SwiftId(folder);
        return new(SyncRecordKind.Folder, id, space, new SyncVersion(clock, CloudDevice),
            Bytes(new JsonObject { ["type"] = "folder", ["value"] = value }), IsTombstone: false);
    }

    private static SyncRecord Tombstone(SyncRecordKind kind, Guid id, Guid space, ulong clock, string reason = "explicitDelete",
        JsonNode? deletedAt = null) => new(kind, id, space, new SyncVersion(clock, CloudDevice),
        Bytes(new JsonObject { ["reason"] = reason, ["deletedAt"] = deletedAt ?? 800000060.0 }), IsTombstone: true);

    #endregion
}
