using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    /// A persistent session that syncs, after its launch stage.
    private static (NativeSessionAuthority Session, NativeSyncAuthority Sync) Syncing(JsonNode session) {
        var owner = new NativeSessionAuthority(Bytes(session));
        var sync = new NativeSyncAuthority(NativeSyncJournal.Fresh(Guid.NewGuid()));
        owner.AttachSync(sync);
        sync.Flush();
        return (owner, sync);
    }

    private static void Rename(NativeSessionAuthority owner, JsonNode session, Guid tab, string title) =>
        owner.PrepareCommand(SpaceCommand(session, "tab.rename", new() { ["tabId"] = tab.ToString(), ["title"] = title }))
            .Commit();

    [Fact]
    public void EditsInQuickSuccessionStageOnceWithTheNewestSession() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session.Remove("disposableSeedMarker");
        var (owner, sync) = Syncing(session);
        var launched = JsonNode.Parse(sync.Snapshot.Read())!;
        Assert.NotEmpty(launched["records"]!.AsArray());

        foreach (var title in new[] { "One", "Two", "Three" }) Rename(owner, session, fixture.Tab, title);
        sync.Flush();

        var journal = JsonNode.Parse(sync.Snapshot.Read())!;
        var tab = journal["records"]!.AsArray().Single(record => record!["id"]!["kind"]!.GetValue<string>() == "tab")!;
        Assert.Equal("Three", tab["payload"]!["value"]!["customTitle"]!.GetValue<string>());
        Assert.Equal(launched["logicalClock"]!.GetValue<ulong>() + 1, journal["logicalClock"]!.GetValue<ulong>());
    }

    [Fact]
    public void TheEditsOfOneHostTurnStageOnceTheTurnEnds() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session.Remove("disposableSeedMarker");
        var owner = new NativeSessionAuthority(Bytes(session));
        using var app = new CrestApp();
        app.AttachWorkspace(owner);
        var sync = new NativeSyncAuthority(NativeSyncJournal.Fresh(Guid.NewGuid()));
        owner.AttachSync(sync);
        sync.Flush();
        _ = app.Drain();
        var launched = sync.Version;

        foreach (var title in new[] { "One", "Two" }) Rename(owner, session, fixture.Tab, title);
        Thread.Sleep(400);
        Assert.Equal(launched, sync.Version);

        app.EndTurn();
        var staged = DrainUntil(app, changes => changes.OfType<SyncJournalChanged>().Any());
        Assert.Single(staged.OfType<SyncJournalChanged>());
        Assert.Equal(launched + 1, sync.Version);
        var tab = JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray()
            .Single(record => record!["id"]!["kind"]!.GetValue<string>() == "tab")!;
        Assert.Equal("Two", tab["payload"]!["value"]!["customTitle"]!.GetValue<string>());
    }

    [Fact]
    public void ADisposableSeedSessionNeverStages() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        Assert.NotNull(session["disposableSeedMarker"]);
        var (owner, sync) = Syncing(session);

        Rename(owner, session, fixture.Tab, "Seeded edit");
        sync.Flush();

        Assert.Empty(JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray());
    }
}
