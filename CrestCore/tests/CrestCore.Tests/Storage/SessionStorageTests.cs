using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The session file the core owns: the format earlier releases wrote, what
/// is on disk when a call returns, and what a crash can and cannot lose.
public sealed unsafe partial class BrowserContractsTests {
    private static int wakes;

    /// A new directory the test owns, removed with everything in it.
    private sealed class StorageDirectory : IDisposable {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "crest-storage-" + Guid.NewGuid().ToString("N"));
        public string File => System.IO.Path.Combine(Path, SessionStorage.FileName);
        public string Recovery => System.IO.Path.Combine(Path, "session.recovery.sqlite");

        public StorageDirectory() => Directory.CreateDirectory(Path);

        public void Dispose() => Directory.Delete(Path, recursive: true);
    }

    private static Dictionary<string, byte[]> StoredParts(string file) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadOnly);
        return connection.Parts().ToDictionary(part => part, part => connection.Read(part)!, StringComparer.Ordinal);
    }

    private static void AssertSameParts(Dictionary<string, byte[]> expected, Dictionary<string, byte[]> actual) {
        Assert.Equal(expected.Keys.Order(StringComparer.Ordinal), actual.Keys.Order(StringComparer.Ordinal));
        foreach (var (part, bytes) in expected) Assert.True(bytes.AsSpan().SequenceEqual(actual[part]), $"{part} changed");
    }

    /// Writes a session file the way an earlier release did: one table, one
    /// row per part, storage version 1.
    private static void WriteStoredFile(string file, JsonObject session, JsonObject? journal, int version = 1) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        connection.Execute("CREATE TABLE checkpoint (part TEXT PRIMARY KEY, data BLOB NOT NULL)");
        connection.Execute($"PRAGMA user_version={version}");
        var core = session.DeepClone().AsObject();
        foreach (var space in core["spaces"]!.AsArray()) {
            var id = Guid.Parse(space!["id"]!["rawValue"]!.GetValue<string>());
            connection.Write("history." + id.ToString("D").ToUpperInvariant(), Bytes(space["history"]!));
            space["history"] = new JsonArray();
        }
        connection.Write("core", Bytes(core));
        if (journal is not null) connection.Write("journal", Bytes(journal));
    }

    /// Makes the file refuse every write to `part`, as a full disk or a
    /// failing device refuses one mid-transaction.
    private static void RefuseWrites(string file, string part) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite);
        foreach (var operation in new[] { "INSERT", "UPDATE" })
            connection.Execute($"CREATE TRIGGER refuse_{operation} BEFORE {operation} ON checkpoint WHEN NEW.part = '{part}' "
                + "BEGIN SELECT RAISE(ABORT, 'refused'); END");
    }

    private static void AcceptWrites(string file) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite);
        connection.Execute("DROP TRIGGER refuse_INSERT");
        connection.Execute("DROP TRIGGER refuse_UPDATE");
    }

    private static JsonObject StoredCore(Dictionary<string, byte[]> parts) => JsonNode.Parse(parts["core"])!.AsObject();

    private static IReadOnlyList<Change> DrainUntil(CrestApp app, Func<IReadOnlyList<Change>, bool> done) {
        var drained = new List<Change>();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!done(drained) && DateTime.UtcNow < deadline) {
            drained.AddRange(app.Drain());
            Thread.Sleep(5);
        }
        return drained;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void CountWake(nint context) {
        Assert.Equal(42, context);
        Interlocked.Increment(ref wakes);
    }

    [Fact]
    public void ASessionTheInstalledAppWroteLoadsAndIsWrittenBackUnchanged() {
        using var directory = new StorageDirectory();
        File.Copy(Path.Combine(AppContext.BaseDirectory, "Storage", "Fixtures", "installed-session.sqlite"), directory.File);
        var original = StoredParts(directory.File);

        using (var app = new CrestApp(new AppConfiguration(directory.Path))) {
            var projection = JsonNode.Parse(app.SessionProjection()!.Output)!;
            var spaces = projection["session"]!["spaces"]!.AsArray();
            Assert.Equal(["Work", "Personal"], spaces.Select(space => space!["name"]!.GetValue<string>()));
            Assert.Equal("deviceOwnerAuthentication", spaces[1]!["accessPolicy"]!.GetValue<string>());
            Assert.Equal([13, 12], spaces.Select(space => space!["history"]!.AsArray().Count));
            Assert.Equal([12, 8], spaces.Select(space => space!["tabs"]!.AsArray().Count));
            var journal = JsonNode.Parse(app.SessionSync!.Snapshot.Read())!;
            Assert.Equal(30, journal["records"]!.AsArray().Count);
            Assert.Equal(27, journal["pendingRecordIDs"]!.AsArray().Count);
        }

        // The launch save found nothing to change, and recovery kept the file as it was.
        AssertSameParts(original, StoredParts(directory.File));
        AssertSameParts(original, StoredParts(directory.Recovery));
    }

    [Fact]
    public void AcceptedEditsAreSavedBehindInOrderAndOnlyNewerRevisionsAreAnnounced() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        using (var app = new CrestApp(new AppConfiguration(directory.Path))) {
            Assert.Null(app.Session);
            app.InstallSession(Bytes(document), []);
            var session = app.Session!;
            for (int edit = 1; edit <= 20; edit++) session.Commit(session.Revision, RenameDelta(document, $"Edit {edit}"));
            var announced = DrainUntil(app, changes => changes.OfType<Saved>().Any(saved => saved.Revision == 21));
            var saved = announced.OfType<Saved>().Select(change => change.Revision).ToArray();
            Assert.Equal(21, saved[^1]);
            Assert.Equal(saved.Order(), saved);
            Assert.Equal(saved.Distinct(), saved);
            Assert.DoesNotContain(announced, change => change is StorageFailed);
        }
        using var reopened = new CrestApp(new AppConfiguration(directory.Path));
        var tabs = JsonNode.Parse(reopened.SessionProjection()!.Output)!["session"]!["spaces"]![0]!["tabs"]!.AsArray();
        Assert.Equal("Edit 20", tabs[0]!["title"]!.GetValue<string>());
    }

    [Fact]
    public void ADurableCommitIsOnDiskWithItsJournalBeforeItReturnsOrNeitherChanges() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        var record = SyncTabRecord(fixture.Tab, fixture.Space, 9, Guid.NewGuid());
        var journal = JournalDocument(record);
        using var app = new CrestApp(new AppConfiguration(directory.Path));
        app.InstallSession(Bytes(document), Bytes(journal));
        var session = app.Session!;
        var sync = app.SessionSync!;
        var loaded = sync.Snapshot;
        _ = DrainUntil(app, changes => changes.OfType<Saved>().Any());
        var before = StoredParts(directory.File);
        var acknowledge = JournalCommand(journal, "acknowledge",
            new() { ["acknowledgements"] = new JsonArray(new JsonObject { ["id"] = record["id"]!.DeepClone() }) });
        using var transaction = sync.Prepare(1, acknowledge)!;
        Assert.True(transaction.Seal());

        var rename = session.PrepareCommand(1,
            SpaceCommand(document, "tab.rename", new() { ["tabId"] = fixture.Tab.ToString(), ["title"] = "Saved with its journal" }));

        RefuseWrites(directory.File, "journal");
        Assert.Throws<StorageException>(() => rename.Commit(Durability.BeforeReturn, transaction));
        Assert.Equal(1UL, session.Revision);
        Assert.Same(loaded, sync.Snapshot);
        AssertSameParts(before, StoredParts(directory.File));

        AcceptWrites(directory.File);
        Assert.Equal(2UL, rename.Commit(Durability.BeforeReturn, transaction));
        var after = StoredParts(directory.File);
        Assert.True(after["core"].AsSpan().SequenceEqual(session.Checkpoint(2).Read("core")));
        Assert.True(after["journal"].AsSpan().SequenceEqual(transaction.Journal.Read()));
        Assert.Same(transaction.Journal, sync.Snapshot);
    }

    [Fact]
    public void AJournalIsNeverWrittenAheadOfTheSessionItWasStagedFrom() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        var record = SyncTabRecord(fixture.Tab, fixture.Space, 9, Guid.NewGuid());
        var journal = JournalDocument(record);
        using var app = new CrestApp(new AppConfiguration(directory.Path));
        app.InstallSession(Bytes(document), Bytes(journal));
        var session = app.Session!;
        session.Commit(1, RenameDelta(document, "Edited before staging"));
        var acknowledge = JournalCommand(journal, "acknowledge",
            new() { ["acknowledgements"] = new JsonArray(new JsonObject { ["id"] = record["id"]!.DeepClone() }) });
        using var transaction = app.SessionSync!.Prepare(2, acknowledge)!;
        Assert.True(transaction.Seal());
        transaction.CommitDurably();

        // Whichever write came first, the journal is on disk with the session it followed.
        var stored = StoredParts(directory.File);
        Assert.True(stored["journal"].AsSpan().SequenceEqual(transaction.Journal.Read()));
        Assert.Equal("Edited before staging", StoredCore(stored)["spaces"]![0]!["tabs"]![0]!["title"]!.GetValue<string>());
    }

    [Fact]
    public void RecoveryKeepsTheSessionExactlyAsLoadedAndRepairIsTheFirstSave() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        // A second Space that reuses the first one's profile and tab: repair must
        // give it identities of its own.
        var twin = document["spaces"]![0]!.DeepClone().AsObject();
        twin["id"] = SwiftId(Guid.NewGuid());
        document["spaces"]!.AsArray().Add(twin);
        WriteStoredFile(directory.File, document, JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid())));
        var written = StoredParts(directory.File);

        using (var app = new CrestApp(new AppConfiguration(directory.Path))) {
            AssertSameParts(written, StoredParts(directory.Recovery));
            var projection = JsonNode.Parse(app.SessionProjection()!.Output)!;
            var spaces = projection["session"]!["spaces"]!.AsArray();
            Assert.NotEqual(spaces[0]!["profile"]!["id"]!.GetValue<string>(), spaces[1]!["profile"]!["id"]!.GetValue<string>());
            // The repaired tab keeps the images of the tab it came from.
            var origin = projection["assets"]!.AsArray().Single(asset => asset!["spaceIndex"]!.GetValue<int>() == 1);
            Assert.Equal(fixture.Tab, Guid.Parse(origin!["sourceTabID"]!["rawValue"]!.GetValue<string>()));
            Assert.NotEqual(fixture.Tab, Guid.Parse(spaces[1]!["tabs"]![0]!["id"]!["rawValue"]!.GetValue<string>()));
        }

        var saved = StoredCore(StoredParts(directory.File));
        var profiles = saved["spaces"]!.AsArray().Select(space => space!["profile"]!["id"]!.GetValue<string>()).ToArray();
        Assert.Equal(2, profiles.Distinct().Count());
        AssertSameParts(written, StoredParts(directory.Recovery));
    }

    [Fact]
    public void AFileTheCoreMustNotUseIsRefusedWithoutWritingToIt() {
        var document = SavedSession().Document["session"]!.AsObject();
        var journal = JournalDocument(SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid()));

        using (var newer = new StorageDirectory()) {
            WriteStoredFile(newer.File, document, journal, version: 2);
            var bytes = File.ReadAllBytes(newer.File);
            Assert.IsType<StorageFromNewerApp>(Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(newer.Path))).Rejection);
            Assert.Equal(bytes, File.ReadAllBytes(newer.File));
        }
        using (var newerJournal = new StorageDirectory()) {
            var future = journal.DeepClone().AsObject();
            future["schemaVersion"] = 2;
            WriteStoredFile(newerJournal.File, document, future);
            Assert.IsType<StorageFromNewerApp>(
                Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(newerJournal.Path))).Rejection);
        }
        using (var incomplete = new StorageDirectory()) {
            WriteStoredFile(incomplete.File, document, journal);
            using (var connection = SqliteConnection.Open(incomplete.File, Sqlite.OpenReadWrite))
                connection.Execute("DELETE FROM checkpoint WHERE part LIKE 'history.%'");
            var bytes = File.ReadAllBytes(incomplete.File);
            var refused = Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(incomplete.Path))).Rejection;
            Assert.Equal(new StorageUnreadable(StorageFailure.Damaged), refused);
            Assert.Equal(bytes, File.ReadAllBytes(incomplete.File));
            Assert.False(File.Exists(incomplete.Recovery));
        }
        using (var restoring = new StorageDirectory()) {
            File.WriteAllBytes(restoring.File + ".restore-pending", []);
            Assert.IsType<StorageRestoreInterrupted>(
                Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(restoring.Path))).Rejection);
            Assert.False(File.Exists(restoring.File));
        }
    }

    [Fact]
    public void TheHostIsWokenOnceForChangesTheCoreStartedAndDrainsThemInOrder() {
        using var directory = new StorageDirectory();
        using var memoryOnly = new AppClient();
        Assert.Equal(CoreStatus.Empty, memoryOnly.Session().Status);

        using var app = new AppClient(directory.Path);
        Assert.Equal(CoreStatus.Empty, app.Session().Status);
        Volatile.Write(ref wakes, 0);
        Assert.Equal(CoreStatus.Ok, app.SetWake(&CountWake, 42));
        Assert.Equal(CoreStatus.Ok, app.Install(Bytes(SavedSession().Document["session"]!), []));
        Assert.Equal(CoreStatus.InvalidState, app.Install(Bytes(SavedSession().Document["session"]!), []));

        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (Volatile.Read(ref wakes) == 0 && DateTime.UtcNow < deadline) Thread.Sleep(5);
        Assert.Equal(1, Volatile.Read(ref wakes));
        Assert.Equal([new Saved(1)], app.Drain());
        Assert.Empty(app.Drain());
        Assert.Equal(CoreStatus.Ok, app.SetWake(null, 0));

        var (status, session, revision, sync, projection) = app.Session();
        Assert.Equal(CoreStatus.Ok, status);
        Assert.Equal(1UL, revision);
        Assert.NotEqual(0UL, session);
        Assert.NotEqual(0UL, sync);
        Assert.NotEqual(0UL, projection);
    }
}
