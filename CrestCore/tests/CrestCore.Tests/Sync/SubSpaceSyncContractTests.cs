using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Sub-Spaces travel as fields of the Space record that older builds keep
/// without reading. Those builds refuse a whole merge when two Space records
/// share a `profileID`, when a Space's `profileID` changes, or when a Space holds
/// more than twelve pins, so a group must never hand them one.
public sealed partial class BrowserContractsTests {
    #region Actions - Older builds

    /// Every Space record carries its Space's own profile, whatever group the
    /// Space joins or leaves, so the records never share a profile and a
    /// record's profile never changes.
    [Fact]
    public void AGroupNeverHandsAnOlderBuildASharedOrChangedProfile() {
        var (primary, subSpace, solo) = (Fixed(2_100), Fixed(2_101), Fixed(2_102));
        var (primaryProfile, subSpaceProfile, soloProfile) = (Fixed(2_190), Fixed(2_191), Fixed(2_192));
        var journal = new JournalUnderTest(Fixed(2_199));

        journal.Stage(SessionOf(SpaceOf(primary, primaryProfile, "Work"),
            Joined(SpaceOf(subSpace, subSpaceProfile, "Client"), primary, primaryProfile, at: 200),
            SpaceOf(solo, soloProfile, "Personal")), at: 300);
        AssertOwnProfiles(journal, (primary, primaryProfile), (subSpace, subSpaceProfile), (solo, soloProfile));
        Assert.Equal(primary, StoredSessionCodec.Identity(journal.Value(SyncRecordKind.Space, subSpace)!["primarySpaceID"]));
        Assert.Equal(primaryProfile, StoredSessionCodec.Identity(journal.Value(SyncRecordKind.Space, subSpace)!["sharedProfileID"]));

        journal.Stage(SessionOf(SpaceOf(primary, primaryProfile, "Work"), Left(SpaceOf(subSpace, subSpaceProfile, "Client"), at: 400),
            SpaceOf(solo, soloProfile, "Personal")), at: 500);
        AssertOwnProfiles(journal, (primary, primaryProfile), (subSpace, subSpaceProfile), (solo, soloProfile));
        var left = journal.Value(SyncRecordKind.Space, subSpace)!;
        Assert.Null(left["primarySpaceID"]);
        Assert.Equal(400, Unix(left["membershipModifiedAt"]), precision: 6);
    }

    /// A legacy editor can change a Space without knowing its independent
    /// position or while carrying the position it knew before a newer move.
    [Fact]
    public void IndependentOrderSurvivesLegacyRecordRewrites() {
        var (work, client, personal) = (Fixed(2_120), Fixed(2_121), Fixed(2_122));
        var (workProfile, clientProfile, personalProfile) = (Fixed(2_190), Fixed(2_191), Fixed(2_192));
        var primary = SpaceOf(work, workProfile, "Work");
        var child = Joined(SpaceOf(client, clientProfile, "Client", tabs: [TabOf(Fixed(2_123))]), work, workProfile, at: 200);
        var solo = SpaceOf(personal, personalProfile, "Personal");
        var initial = SessionOf(primary, child, solo);
        var journal = new JournalUnderTest(Fixed(2_129));
        journal.Stage(initial, at: 300);
        var legacyClient = journal.Record(SyncRecordKind.Space, client)!;
        using var device = new SyncingDevice(initial, journal);
        device.Send(workspace => new ReorderSpaces(workspace, [work, personal, client]));

        // Older clients can continue to materialize the group as a block.
        Assert.Equal([work, client, personal], device.Journal.Values(SyncRecordKind.Space)
            .OrderBy(value => value["orderToken"]!.GetValue<string>(), StringComparer.Ordinal)
            .Select(value => StoredSessionCodec.Identity(value["id"])));
        var firstRecords = device.Journal.Records.Where(record => record["id"]!["kind"]!.GetValue<string>() == SyncRecordKind.Space.Name).ToArray();

        var firstOrder = device.Merge(Edited(legacyClient, 100, Fixed(2_128), value => value["name"] = "Renamed"));
        Assert.Equal([work, personal, client], Ids(firstOrder["spaces"]));
        Assert.Equal("Renamed", StoredSessionCodec.DecodeSession(firstOrder).Space(client)!.Settings.Name);

        device.Send(workspace => new SetSpaceIdentity(workspace, personal, "Home", "house", SpaceAccent.Indigo));
        device.Send(workspace => new ReorderSpaces(workspace, [client, personal, work]));
        Assert.Equal([client, personal, work], Ids(device.StoredSession["spaces"]));
        Assert.Equal("Home", device.Journal.Value(SyncRecordKind.Space, personal)!["name"]!.GetValue<string>());
        Assert.Equal([client, personal, work], Ids(device.Merge(firstRecords.Select(record =>
            Edited(record, 200, Fixed(2_128), _ => { })))["spaces"]));

        var window = device.Open(client, Fixed(2_123));
        var added = Fixed(2_124);
        device.Edit(workspace => new AddSubSpace(workspace, window, added, client));
        Assert.Equal([client, added, personal, work], Ids(device.Journal.Materialize(device.Session)["spaces"]));

        device.Send(workspace => new SeparateSpace(workspace, client));
        Assert.Equal([added, personal, work, client], Ids(device.Journal.Materialize(device.Session)["spaces"]));
        device.Send(workspace => new JoinSpace(workspace, client, personal));
        Assert.Equal([added, personal, client, work], Ids(device.Journal.Materialize(device.Session)["spaces"]));
    }

    /// Staging a partially received reorder must leave the remaining
    /// independent positions free to arrive from the device that made it.
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void IndependentOrderSurvivesArrivalInSeveralBatches(bool joinsAnotherSpace) {
        var (work, client, personal, family) = (Fixed(2_130), Fixed(2_131), Fixed(2_132), Fixed(2_133));
        var workSpace = SpaceOf(work, Fixed(2_180), "Work");
        var clientSpace = Joined(SpaceOf(client, Fixed(2_181), "Client"), work, Fixed(2_180), at: 200);
        var personalSpace = SpaceOf(personal, Fixed(2_182), "Personal");
        var familySpace = Joined(SpaceOf(family, Fixed(2_183), "Family"), personal, Fixed(2_182), at: 200);
        var initial = SessionOf(workSpace, clientSpace, personalSpace, familySpace);
        var sender = new JournalUnderTest(Fixed(2_138));
        sender.Stage(initial, at: 300);
        var receiver = new JournalUnderTest(Fixed(2_139));
        receiver.Merge(sender.Records);
        var reorderedSession = Canonical(SessionOf(personalSpace, workSpace, familySpace, clientSpace));
        sender = new(sender.Journal.Stage(reorderedSession, SyncDeletionReason.Superseded, At(400), reorderedSpaces: true));
        var first = sender.Record(SyncRecordKind.Space, personal)!;
        var local = StoredSessionCodec.DecodeSession(initial);

        var partial = NativeSyncSessionTransition.Prepare(receiver.Journal, local, new JsonArray(first.DeepClone()),
            replacing: false, StoredSessionCodec.Date(At(500)), emptySpace: null, access: null, new TestIds());
        Assert.Equal([personal, work, client, family], partial.Session.Spaces.Select(space => space.Id));
        var beforeRest = new JournalUnderTest(partial.Journal);
        var beforeRestSession = partial.Session;
        Guid[] added = [];
        if (joinsAnotherSpace) {
            var (parent, solo, joining) = (Fixed(2_134), Fixed(2_135), Fixed(2_136));
            using var device = new SyncingDevice(StoredSessionCodec.Encode(partial.Session), beforeRest);
            var window = device.Open(personal, partial.Session.Space(personal)!.Tabs[0].Id);
            foreach (var id in new[] { parent, solo, joining })
                device.Edit(workspace => new CreateSpace(workspace, window, id));
            device.Send(workspace => new JoinSpace(workspace, joining, parent));
            beforeRest = device.Journal;
            beforeRestSession = StoredSessionCodec.DecodeSession(device.Session);
            added = [parent, joining, solo];
        }
        Assert.All(new[] { work, client, family }, space => {
            var partialSpace = beforeRest.Value(SyncRecordKind.Space, space)!;
            Assert.Null(partialSpace["independentOrderToken"]);
            Assert.Null(partialSpace["positionModifiedAt"]);
        });

        var rest = new JsonArray(new[] { work, client, family }.Select(space => sender.Record(SyncRecordKind.Space, space)!.DeepClone()).ToArray());
        var complete = NativeSyncSessionTransition.Prepare(beforeRest.Journal, beforeRestSession, rest,
            replacing: false, StoredSessionCodec.Date(At(600)), emptySpace: null, access: null, new TestIds());
        Assert.Equal([personal, work, family, client, .. added], complete.Session.Spaces.Select(space => space.Id));
        var familyPosition = new JournalUnderTest(complete.Journal).Value(SyncRecordKind.Space, family)!;
        Assert.Equal(400, Unix(familyPosition["positionModifiedAt"]), precision: 6);
    }

    [Fact]
    public void ANewSpaceCanBePlacedBetweenSpacesCreatedConcurrently() {
        var (work, client, personal) = (Fixed(2_150), Fixed(2_151), Fixed(2_152));
        var workSpace = SpaceOf(work, Fixed(2_170), "Work");
        var clientSpace = Joined(SpaceOf(client, Fixed(2_171), "Client"), work, Fixed(2_170), at: 200);
        var personalSpace = SpaceOf(personal, Fixed(2_172), "Personal");
        var (first, second, between) = (Fixed(2_153), Fixed(2_154), Fixed(2_155));
        var firstSpace = Joined(SpaceOf(first, Fixed(2_173), "First"), work, Fixed(2_170), at: 400);
        var secondSpace = Joined(SpaceOf(second, Fixed(2_174), "Second"), work, Fixed(2_170), at: 400);
        var betweenSpace = Joined(SpaceOf(between, Fixed(2_175), "Between"), work, Fixed(2_170), at: 500);
        var local = new JournalUnderTest(Fixed(2_158));
        local.Stage(SessionOf(clientSpace, personalSpace, workSpace), at: 300);
        var remote = new JournalUnderTest(Fixed(2_159));
        remote.Merge(local.Records);
        local.Stage(SessionOf(clientSpace, firstSpace, personalSpace, workSpace), at: 400);
        remote.Stage(SessionOf(clientSpace, secondSpace, personalSpace, workSpace), at: 400);
        Assert.Equal(local.Value(SyncRecordKind.Space, first)!["independentOrderToken"]!.GetValue<string>(),
            remote.Value(SyncRecordKind.Space, second)!["independentOrderToken"]!.GetValue<string>());
        local.Merge(remote.Record(SyncRecordKind.Space, second)!);

        var expanded = SessionOf(clientSpace, firstSpace, betweenSpace, secondSpace, personalSpace, workSpace);
        local.Stage(expanded, at: 500);
        Assert.Equal([client, first, between, second, personal, work], Ids(local.Materialize(expanded)["spaces"]));
    }

    [Fact]
    public void AFailedSpaceReorderLeavesItsSessionAndJournalTogether() {
        var (work, client, personal) = (Fixed(2_140), Fixed(2_141), Fixed(2_142));
        var local = SessionOf(SpaceOf(work, Fixed(2_184), "Work"),
            Joined(SpaceOf(client, Fixed(2_185), "Client"), work, Fixed(2_184), at: 200),
            SpaceOf(personal, Fixed(2_186), "Personal"));
        var seeded = new JournalUnderTest(Fixed(2_149));
        seeded.Stage(local, at: 300);
        using var directory = new StorageDirectory();
        using var device = StoredSyncing(directory, new JsonObject { ["session"] = Canonical(local) }, journal: seeded.Document);
        device.Sync.Flush();
        var (session, journal, parts) = (device.Session.Current, device.Sync.Snapshot, StoredParts(directory.File));
        RefuseWrites(directory.File, "journal");

        var move = new ReorderSpaces(device.Workspace, [client, personal, work]);
        var refusal = Assert.Throws<Rejected>(() => device.App.Send(move));
        Assert.IsType<SaveFailed>(refusal.Rejection);
        Assert.Same(session, device.Session.Current);
        Assert.Same(journal, device.Sync.Snapshot);
        AssertSameParts(parts, StoredParts(directory.File));

        AcceptWrites(directory.File);
        device.App.Send(move);
        var saved = StoredParts(directory.File);
        Assert.Equal([client, personal, work], Ids(StoredCore(saved)["spaces"]));
        Assert.True(saved["journal"].AsSpan().SequenceEqual(device.Sync.Snapshot.Read()));
    }

    #endregion

    #region Actions - Membership

    /// A copy from a build that never learned the Space joined a group holds
    /// no time for it, and a copy with no time loses: the membership survives
    /// whichever copy wins the record. A later choice to leave wins over an
    /// earlier one to join, however the copies arrive.
    [Fact]
    public void AnOlderCopyCannotUndoAGroupAndALaterLeaveWins() {
        var (primary, subSpace) = (Fixed(2_200), Fixed(2_201));
        var journal = new JournalUnderTest(Fixed(2_299));
        journal.Stage(SessionOf(SpaceOf(primary, Fixed(2_290)), Joined(SpaceOf(subSpace, Fixed(2_291)), primary, Fixed(2_290), at: 300)),
            at: 300);
        var joined = Edited(journal.Record(SyncRecordKind.Space, subSpace)!, 10, Fixed(2_210), _ => { });
        var older = Edited(joined, 100, Fixed(2_211), value => {
            value.Remove("primarySpaceID");
            value.Remove("sharedProfileID");
            value.Remove("membershipModifiedAt");
            value["name"] = "Renamed";
        });

        var kept = ConvergedValue(SyncRecordKind.Space, subSpace, joined, older);
        Assert.Equal("Renamed", kept["name"]!.GetValue<string>());
        Assert.Equal(primary, StoredSessionCodec.Identity(kept["primarySpaceID"]));
        Assert.Equal(300, Unix(kept["membershipModifiedAt"]), precision: 6);

        var leaving = Edited(joined, 5, Fixed(2_212), value => {
            value.Remove("primarySpaceID");
            value.Remove("sharedProfileID");
            value["membershipModifiedAt"] = At(400);
        });
        var left = ConvergedValue(SyncRecordKind.Space, subSpace, joined, leaving);
        Assert.Null(left["primarySpaceID"]);
        Assert.Equal(400, Unix(left["membershipModifiedAt"]), precision: 6);
    }

    /// A group shares its protection, so a Space's content blocking and data
    /// retention merge by when someone chose them: a copy that wins the record
    /// with an older choice keeps its other browsing choices, not its
    /// protection.
    [Fact]
    public void ANewerProtectionChoiceOutlivesACopyThatWinsTheRecord() {
        var space = Fixed(2_250);
        var journal = new JournalUnderTest(Fixed(2_299));
        journal.Stage(SessionOf(SpaceOf(space, Fixed(2_290))), at: 300);
        var record = journal.Record(SyncRecordKind.Space, space)!;
        var protecting = Edited(record, 10, Fixed(2_251), value => {
            value["browsingPreferences"]!["contentBlockingPolicy"] = "balanced";
            value["browsingPreferences"]!["dataRetention"]!["history"] = "oneWeek";
            value["protectionModifiedAt"] = At(500);
        });
        var older = Edited(record, 100, Fixed(2_252), value => {
            value["browsingPreferences"]!["contentBlockingPolicy"] = "off";
            value["browsingPreferences"]!["searchSuggestionsEnabled"] = true;
            value["protectionModifiedAt"] = At(400);
        });

        var kept = ConvergedValue(SyncRecordKind.Space, space, protecting, older);
        var browsing = kept["browsingPreferences"]!;
        Assert.Equal("balanced", browsing["contentBlockingPolicy"]!.GetValue<string>());
        Assert.Equal("oneWeek", browsing["dataRetention"]!["history"]!.GetValue<string>());
        Assert.True(browsing["searchSuggestionsEnabled"]!.GetValue<bool>());
        Assert.Equal(500, Unix(kept["protectionModifiedAt"]), precision: 6);
    }

    /// Moving a Sub-Space on another device changes its place in the
    /// workspace while it continues to browse with its primary's profile.
    [Fact]
    public void ARemoteMovePlacesASubSpaceAcrossGroupsAndKeepsItsMembership() {
        var (primary, subSpace, solo) = (Fixed(2_300), Fixed(2_301), Fixed(2_302));
        var local = SessionOf(SpaceOf(primary, Fixed(2_390), "Work"), Joined(SpaceOf(subSpace, Fixed(2_391), "Client"), primary,
            Fixed(2_390), at: 200), SpaceOf(solo, Fixed(2_392), "Personal"));
        var journal = new JournalUnderTest(Fixed(2_399));
        journal.Stage(local, at: 300);
        var last = journal.Values(SyncRecordKind.Space).Select(value => value["orderToken"]!.GetValue<string>()).Max(StringComparer.Ordinal)!;
        journal.Merge(Edited(journal.Record(SyncRecordKind.Space, subSpace)!, 900, Fixed(2_310),
            value => value["orderToken"] = last + "z"));

        var materialized = journal.Materialize(local);
        Assert.Equal([primary, solo, subSpace], Ids(materialized["spaces"]));
        var session = StoredSessionCodec.DecodeSession(materialized);
        var member = session.Space(subSpace)!;
        Assert.Equal(primary, member.PrimaryId);
        Assert.Equal(session.Space(primary)!.ProfileId, member.ProfileId);
        Assert.Null(SessionIdentities.Flaw(session));
    }

    /// Sub-Spaces whose primary is gone stay together: the first of them leads
    /// the rest and keeps the profile they browse with.
    [Fact]
    public void SubSpacesOfAPrimaryThatIsGoneFollowTheFirstOfThem() {
        var (gone, profile) = (Guid.NewGuid(), Guid.NewGuid());
        var stamp = DateTimeOffset.Parse("2026-10-25T12:00:00Z");
        var (solo, first, second) = (NewSpace(), NewSpace(), NewSpace());
        var session = new SessionState([solo, first with { Membership = new(gone, profile, stamp) },
            second with { Membership = new(gone, profile, stamp.AddSeconds(1)) }], null, null, [], null);

        var repaired = NativeSessionMaintenance.Repair(session, stamp, null, new SystemIdSource(), out _);

        var (leader, follower) = (repaired.Spaces[1], repaired.Spaces[2]);
        Assert.Null(leader.PrimaryId);
        Assert.Equal(profile, leader.ProfileId);
        Assert.Equal(leader.Id, follower.PrimaryId);
        Assert.Equal(profile, follower.ProfileId);
        Assert.Null(SessionIdentities.Flaw(repaired));
    }

    #endregion

    #region Actions - Deletion

    /// Deleting a Space erases its own profile and the one it browses with,
    /// but never one a Space that stays browses with: a Sub-Space takes only
    /// its unused profile, a primary with Sub-Spaces takes nothing, and the
    /// last Space of a group takes the group's profile.
    [Fact]
    public void DeletingASpaceNeverErasesAProfileAnotherSpaceBrowsesWith() {
        var stamp = DateTimeOffset.Parse("2026-10-25T12:00:00Z");
        var (primary, solo) = (NewSpace(), NewSpace());
        var subSpace = NewSpace() with { Membership = SpaceMembership.Joining(primary, stamp) };
        var session = new SessionState([primary, subSpace, solo], null, null, [], null);

        Assert.Equal([subSpace.OwnProfileId], session.Deleting(subSpace, Guid.NewGuid()).Erasing);
        Assert.Empty(session.Deleting(primary, Guid.NewGuid()).Erasing);
        Assert.Equal([solo.OwnProfileId], session.Deleting(solo, Guid.NewGuid()).Erasing);
        Assert.Equal([primary.OwnProfileId], session.Deleting(primary, Guid.NewGuid(), new HashSet<Guid> { subSpace.Id }).Erasing);
        Assert.Equal([subSpace.OwnProfileId, primary.OwnProfileId],
            session.Deleting(subSpace, Guid.NewGuid(), new HashSet<Guid> { primary.Id }).Erasing);
    }

    #endregion

    #region Actions - Privacy

    /// The lock guards a session, so a Space is locked while any Space that
    /// browses with its profile is, whatever its own policy says.
    [Fact]
    public void ASpaceIsLockedWhileAnotherSpaceOfItsSessionIs() {
        var (primary, subSpace, tab) = (Fixed(2_400), Fixed(2_401), Fixed(2_410));
        var locked = SpaceOf(primary, Fixed(2_490), "Work");
        locked["accessPolicy"] = "deviceOwnerAuthentication";
        using var device = new TestDevice(SessionOf(locked,
            Joined(SpaceOf(subSpace, Fixed(2_491), "Client", tabs: [TabOf(tab)]), primary, Fixed(2_490), at: 100)));

        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new RenameTab(device.Workspace, subSpace, tab, "Leaked"))).Rejection);
    }

    /// An imported Space arrives on its own: the group it had where it was
    /// exported never joins it to a Space here.
    [Fact]
    public void AnImportedSpaceJoinsNoGroup() {
        var (existing, imported) = (Fixed(2_500), Fixed(2_501));
        using var device = new TestDevice(SessionOf(SpaceOf(existing, Fixed(2_590), "Work", tabs: [TabOf(Fixed(2_510))])));
        var window = device.Open(existing, (existing, Fixed(2_510)));

        device.Send(new ImportSpaces(device.Workspace, window, ReadSpaces(
            Joined(SpaceOf(imported, Fixed(2_591), "Client", tabs: [TabOf(Fixed(2_511))]), existing, Fixed(2_590), at: 100))));

        var arrived = Assert.Single(device.Authority.Current.Spaces, space => space.Settings.Name == "Client");
        Assert.Null(arrived.Membership);
        Assert.Equal(arrived.OwnProfileId, arrived.ProfileId);
    }

    #endregion

    #region Actions - Fixtures

    /// `space`, a Space in the stored format, as a Sub-Space of `primary`, which
    /// browses with `profile`, as someone chose `at` seconds after 1970.
    private static JsonObject Joined(JsonObject space, Guid primary, Guid profile, double at) {
        space["primarySpaceID"] = SwiftId(primary);
        space["sharedProfileID"] = profile.ToString("D").ToUpperInvariant();
        space["membershipModifiedAt"] = At(at);
        return space;
    }

    /// `space`, a Space in the stored format, as one that left its group `at`
    /// seconds after 1970.
    private static JsonObject Left(JsonObject space, double at) {
        space["membershipModifiedAt"] = At(at);
        return space;
    }

    /// Asserts that each Space record the journal holds carries exactly the
    /// own profile `expected` pairs with it, and no two share one.
    private static void AssertOwnProfiles(JournalUnderTest journal, params (Guid Space, Guid Profile)[] expected) {
        var profiles = journal.Values(SyncRecordKind.Space).Select(value => StoredSessionCodec.Identity(value["profileID"])).ToList();
        Assert.Equal(profiles.Count, profiles.Distinct().Count());
        foreach (var (space, profile) in expected)
            Assert.Equal(profile, StoredSessionCodec.Identity(journal.Value(SyncRecordKind.Space, space)!["profileID"]));
    }

    /// A new ordinary Space of its own.
    private static SpaceState NewSpace() =>
        SpaceTemplate.For(privateBrowsing: false).Make(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid, number: 1, DateTimeOffset.UnixEpoch);

    #endregion
}
