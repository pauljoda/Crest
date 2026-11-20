using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    [Fact]
    public async Task ASyncHandoverWaitsForEveryInFlightProfileErasure() {
        var (departing, sharedProfile, other, successor, successorProfile) = (Fixed(8_710), Fixed(8_711),
            Fixed(8_720), Fixed(8_730), Fixed(8_731));
        var localTab = Fixed(8_723);
        var session = Canonical(SessionOf(SpaceOf(departing, sharedProfile, "Work"),
            SpaceOf(other, Fixed(8_721), "Other", tabs: [NativeTabOf(localTab, "settings", "Settings")])));
        using var directory = new StorageDirectory();
        var ids = new PausingIds();
        var clock = new TestClock(DateTimeOffset.FromUnixTimeSeconds(1_800_000_200));
        using var stored = StoredSyncing(directory, new JsonObject { ["session"] = session }, clock: clock, ids: ids);
        var (webKit, webKitBinding, chromium, chromiumBinding) = IdleEngines(stored.App);

        stored.App.Send(new MergeSyncRecords([Tombstone(SyncRecordKind.Space, departing, departing, clock: 1_000)]));
        Assert.Equal([sharedProfile], stored.Session.Current.PendingDeletion(departing)!.Erasing);
        var handover = CloudSpace(successor, successorProfile, clock: 1_001);
        var body = JsonNode.Parse(handover.Body)!.AsObject();
        body["value"]!["sharedProfileID"] = sharedProfile.ToString("D").ToUpperInvariant();
        body["value"]!["membershipModifiedAt"] = 1_800_000_100.0;
        var incoming = new MergeSyncRecords([handover with { Body = Bytes(body) }, CloudTab(localTab, successor, clock: 1_002)]);
        var (before, journal, parts) = (stored.Session.Current, stored.Sync.Snapshot, StoredParts(directory.File));

        var merging = Task.Run(() => {
            // The cloud tab collides with the other Space's local tab, so
            // preparation draws an identity before taking the app's lock.
            ids.PauseNextDraw();
            return stored.App.Send(incoming);
        });
        try {
            var prepared = await Task.WhenAny(ids.Paused, merging).WaitAsync(TimeSpan.FromSeconds(10));
            if (prepared == merging) await merging;
            Assert.Same(ids.Paused, prepared);
            await Task.Run(() => stored.App.Send(new DeleteProfileData(Guid.NewGuid(), sharedProfile, Ephemeral: false)))
                .WaitAsync(TimeSpan.FromSeconds(10));
        } finally {
            ids.Resume();
        }
        var refused = await Assert.ThrowsAsync<Rejected>(() => merging.WaitAsync(TimeSpan.FromSeconds(10)));
        Assert.Equal(new SyncStagingRefused(SyncStagingFailure.NotSaved), refused.Rejection);
        Assert.Same(before, stored.Session.Current);
        Assert.Same(journal, stored.Sync.Snapshot);
        AssertSameParts(parts, StoredParts(directory.File));

        // An unrelated cloud change goes through while the erasure runs.
        var otherTab = Fixed(8_722);
        stored.App.Send(new MergeSyncRecords([CloudTab(otherTab, other, clock: 1_003)]));
        Assert.Contains(stored.Session.Current.KnownSpace(other).Tabs, tab => tab.Id == otherTab);

        var webKitErasure = Assert.Single(webKitBinding.Commands.OfType<EraseProfileData>());
        var chromiumErasure = Assert.Single(chromiumBinding.Commands.OfType<EraseProfileData>());
        stored.App.Report(webKit, new DataErased(webKitErasure.ErasureId, Erased: true));
        Assert.IsType<SyncStagingRefused>(Assert.Throws<Rejected>(() => stored.App.Send(incoming)).Rejection);
        Assert.Null(stored.Session.Current.Space(successor));

        stored.App.Report(chromium, new DataErased(chromiumErasure.ErasureId, Erased: true));
        Assert.Empty(stored.App.Send(new MergeCloudSnapshot(incoming.Records)));
        var settled = stored.Session.Current;
        Assert.Equal(sharedProfile, settled.KnownSpace(successor).ProfileId);
        var deletion = Assert.IsType<SpaceDeletionState>(settled.PendingDeletion(departing));
        Assert.Equal(successor, deletion.SuccessorId);
        Assert.Empty(deletion.Erasing);

        // An old request cannot erase the shared profile even after the
        // previous owner's pending deletion has been removed.
        stored.App.Send(new FinishDeletingSpace(stored.Workspace, Guid.NewGuid(), departing, deletion.Id));
        Assert.Null(stored.Session.Current.PendingDeletion(departing));
        Assert.Equal(new ProfileInUse(sharedProfile), Assert.Throws<Rejected>(() =>
            stored.App.Send(new DeleteProfileData(Guid.NewGuid(), sharedProfile, Ephemeral: false))).Rejection);
        Assert.Single(webKitBinding.Commands.OfType<EraseProfileData>());
        Assert.Single(chromiumBinding.Commands.OfType<EraseProfileData>());
    }

    #endregion
}
