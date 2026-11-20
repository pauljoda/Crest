using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Actions - Primary succession

    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public void APrimaryTombstoneKeepsSharedPinsWithTheSuccessor(bool successorArrived, bool pinArrived) {
        var (work, workProfile, client, clientProfile, pin) = (Fixed(8_300), Fixed(8_301), Fixed(8_400), Fixed(8_401), Fixed(8_302));
        var otherPin = Fixed(8_303);
        var (firstChild, firstProfile) = (Fixed(8_410), Fixed(8_411));
        var session = Canonical(SessionOf(
            SpaceOf(work, workProfile, "Work", tabs: [TabOf(pin, placement: "pinned"), TabOf(otherPin, placement: "pinned")]),
            Joined(SpaceOf(firstChild, firstProfile, "First client"), work, workProfile, at: 1_800_000_000),
            Joined(SpaceOf(client, clientProfile, "Client"), work, workProfile, at: 1_800_000_000)));
        using var directory = new StorageDirectory();
        var receiveTime = new TestClock(DateTimeOffset.FromUnixTimeSeconds(1_800_000_200));
        using var stored = StoredSyncing(directory, new JsonObject { ["session"] = session }, clock: receiveTime);
        var window = Guid.NewGuid();
        stored.App.Send(new OpenWindow(window, stored.Workspace, Saved: false, CopyingWindowId: null,
            ShowingSpaceId: client, ShowingTabs: [], RestoresTabs: true));
        var handover = CloudSpace(client, clientProfile, clock: 1_001);
        var spaceBody = JsonNode.Parse(handover.Body)!.AsObject();
        spaceBody["value"]!["sharedProfileID"] = workProfile.ToString("D").ToUpperInvariant();
        spaceBody["value"]!["membershipModifiedAt"] = 1_800_000_100.0;
        handover = handover with { Body = Bytes(spaceBody) };
        List<SyncRecord> records = [Tombstone(SyncRecordKind.Space, work, work, clock: 1_000)];
        if (successorArrived) records.Add(handover);
        if (pinArrived) {
            records.Add(TransferredPin(otherPin, 1_002, "4000000000000000"));
            records.Add(TransferredPin(pin, 1_003, "8000000000000000"));
        }

        Assert.Empty(stored.App.Send(new MergeSyncRecords(records)));

        Guid? operation = null;
        if (!successorArrived) {
            var waiting = stored.Session.Current;
            var intent = Assert.IsType<SpaceDeletionState>(waiting.PendingDeletion(work));
            operation = intent.Id;
            Assert.Null(intent.SuccessorId);
            Assert.Empty(intent.Erasing);
            Assert.Equal(work, waiting.KnownSpace(client).PrimaryId);
            Assert.Contains(waiting.KnownSpace(work).Tabs, tab => tab.Id == pin && tab.IsPinned);
            Assert.IsType<InvalidNewPrimary>(Assert.Throws<Rejected>(() =>
                stored.App.Send(new BeginDeletingSpace(stored.Workspace, window, work, intent.Id))).Rejection);
            Assert.IsType<InvalidNewPrimary>(Assert.Throws<Rejected>(() =>
                stored.App.Send(new FinishDeletingSpace(stored.Workspace, window, work, intent.Id))).Rejection);
            Assert.Empty(stored.App.Send(new MergeSyncRecords([handover])));
        }

        var after = stored.Session.Current;
        var deletion = Assert.IsType<SpaceDeletionState>(after.PendingDeletion(work));
        if (operation is { } known) Assert.Equal(known, deletion.Id);
        Assert.Equal(client, deletion.SuccessorId);
        Assert.Empty(deletion.Erasing);
        Assert.Equal(client, after.KnownSpace(firstChild).PrimaryId);
        Assert.DoesNotContain(after.KnownSpace(work).Tabs, tab => tab.IsPinned);
        Guid[] expectedPins = pinArrived ? [otherPin, pin] : [pin, otherPin];
        Assert.Equal(expectedPins, after.KnownSpace(client).Tabs.Where(tab => tab.IsPinned).Select(tab => tab.Id));

        var departure = CloudSpace(firstChild, firstProfile, clock: 1_004);
        var departureBody = JsonNode.Parse(departure.Body)!.AsObject();
        // This person left after the sender's handover and before this
        // device received it. The inferred reparenting cannot undo that.
        departureBody["value"]!["membershipModifiedAt"] = 1_800_000_120.0;
        Assert.Empty(stored.App.Send(new MergeSyncRecords([departure with { Body = Bytes(departureBody) }])));
        Assert.Null(stored.Session.Current.KnownSpace(firstChild).PrimaryId);

        SyncRecord TransferredPin(Guid id, ulong clock, string token) {
            var transferred = CloudTab(id, client, clock);
            var tabBody = JsonNode.Parse(transferred.Body)!.AsObject();
            tabBody["value"]!["placement"] = "pinned";
            tabBody["value"]!["orderToken"] = token;
            return transferred with { Body = Bytes(tabBody) };
        }
    }

    [Fact]
    public void AnOfflineReceiverKeepsAProfileAndItsCredentialsWhenAnotherSpaceTakesOver() {
        var (work, workProfile, client, clientProfile) = (Fixed(8_100), Fixed(8_101), Fixed(8_200), Fixed(8_201));
        var session = Canonical(SessionOf(
            SpaceOf(work, workProfile, "Work", tabs: [TabOf(Fixed(8_102))]),
            SpaceOf(client, clientProfile, "Client", tabs: [TabOf(Fixed(8_202))])));
        using var directory = new StorageDirectory();
        using var stored = StoredSyncing(directory, new JsonObject { ["session"] = session });
        Assert.Equal(clientProfile, stored.Session.Current.KnownSpace(client).ProfileId);

        var handover = CloudSpace(client, clientProfile, clock: 1_000);
        var body = JsonNode.Parse(handover.Body)!.AsObject();
        body["value"]!["sharedProfileID"] = workProfile.ToString("D").ToUpperInvariant();
        body["value"]!["membershipModifiedAt"] = 1_800_000_100.0;
        var tombstone = Tombstone(SyncRecordKind.Space, work, work, clock: 1_001);

        Assert.Empty(stored.App.Send(new MergeSyncRecords([handover with { Body = Bytes(body) }, tombstone])));

        var after = stored.Session.Current;
        Assert.Equal(workProfile, after.KnownSpace(client).ProfileId);
        var deletion = Assert.IsType<SpaceDeletionState>(after.PendingDeletion(work));
        Assert.Equal(client, deletion.SuccessorId);
        Assert.DoesNotContain(workProfile, deletion.Erasing);
    }

    [Fact]
    public void ReopeningAPendingDeletionProtectsTheProfileItsSuccessorUses() {
        var (work, workProfile, client, clientProfile, operation) = (Fixed(8_500), Fixed(8_501), Fixed(8_600), Fixed(8_601), Fixed(8_502));
        var successor = SpaceOf(client, clientProfile, "Client");
        successor["sharedProfileID"] = workProfile.ToString("D").ToUpperInvariant();
        successor["membershipModifiedAt"] = At(1_800_000_100);
        var session = Canonical(SessionOf(SpaceOf(work, workProfile, "Work"), successor));
        session["spaceDeletions"] = new JsonArray(new JsonObject {
            ["spaceID"] = SwiftId(work),
            ["profileID"] = SwiftId(workProfile),
            ["operationID"] = SwiftId(operation),
            ["erasedProfileIDs"] = new JsonArray(SwiftId(workProfile))
        });
        using var directory = new StorageDirectory();
        using var stored = StoredSyncing(directory, new JsonObject { ["session"] = session });

        var after = stored.Session.Current;
        var deletion = Assert.IsType<SpaceDeletionState>(after.PendingDeletion(work));
        Assert.Equal(operation, deletion.Id);
        Assert.Equal(workProfile, after.KnownSpace(client).ProfileId);
        Assert.Equal(client, deletion.SuccessorId);
        Assert.Empty(deletion.Erasing);
    }

    #endregion
}
