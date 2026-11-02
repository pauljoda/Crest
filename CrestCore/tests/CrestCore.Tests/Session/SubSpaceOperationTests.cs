using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A group shares one session, so it shares what guards and records it: one
/// lock, one owner of its pins and history, and an owner that hands them on
/// when it goes. A private window's session is never shared.
public sealed partial class BrowserContractsTests {
    #region Actions - Lock

    /// Unlocking any Space of a group opens all of it and locking any locks
    /// all of it. Joining never lowers protection: the joining Space keeps the
    /// group's grant, and a locked Space locks the group it joins. Separating
    /// keeps the Space open where the group was.
    [Fact]
    public void AGroupLocksAndUnlocksAsOneAndJoiningNeverLowersItsProtection() {
        var (primary, joining, open) = (Fixed(3_100), Fixed(3_101), Fixed(3_102));
        var (primaryTab, joiningTab, openTab) = (Fixed(3_110), Fixed(3_111), Fixed(3_112));
        using var device = new TestDevice(SessionOf(
            Locked(SpaceOf(primary, Fixed(3_190), "Work", tabs: [TabOf(primaryTab)])),
            SpaceOf(joining, Fixed(3_191), "Client", tabs: [TabOf(joiningTab)]),
            SpaceOf(open, Fixed(3_192), "Personal", tabs: [TabOf(openTab)])));
        void Rename(Guid space, Guid tab) => device.Send(new RenameTab(device.Workspace, space, tab, "Renamed"));
        void Refused(Guid space, Guid tab) =>
            Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => Rename(space, tab)).Rejection);

        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new JoinSpace(device.Workspace, joining, primary))).Rejection);
        Unlock(device.Send, device.Workspace, primary);
        device.Send(new JoinSpace(device.Workspace, joining, primary));
        Assert.True(device.Authority.Current.Space(joining)!.Settings.RequiresAuthentication);
        Rename(joining, joiningTab);

        device.Send(new LockSpace(joining));
        Refused(primary, primaryTab);
        Refused(joining, joiningTab);
        Unlock(device.Send, device.Workspace, joining);
        Rename(primary, primaryTab);

        device.Send(new SeparateSpace(device.Workspace, joining));
        var separated = device.Authority.Current.Space(joining)!;
        Assert.Null(separated.PrimaryId);
        Assert.Equal(separated.OwnProfileId, separated.ProfileId);
        Rename(joining, joiningTab);

        device.Send(new JoinSpace(device.Workspace, joining, open));
        Assert.True(device.Authority.Current.Space(open)!.Settings.RequiresAuthentication);
        Rename(open, openTab);
    }

    /// Members that drifted apart through sync take the latest choice, and
    /// among equal times a lock set on any member locks the group.
    [Fact]
    public void AGroupTakesTheLatestLockChoiceAndALockWinsATie() {
        var stamp = DateTimeOffset.Parse("2026-10-25T12:00:00Z");
        SpaceState Choosing(SpaceState space, SpaceAccessPolicy policy, int seconds) => space with {
            Settings = space.Settings with { AccessPolicy = policy, AccessPolicyModifiedAt = stamp.AddSeconds(seconds) }
        };
        var primary = NewSpace();
        var member = NewSpace() with { Membership = SpaceMembership.Joining(primary, stamp) };
        IReadOnlyList<SpaceState> Settled(SpaceState first, SpaceState second) => SpaceGroup.Regrouped([first, second], new HashSet<Guid>());

        var later = Settled(Choosing(primary, SpaceAccessPolicy.Open, 200), Choosing(member, SpaceAccessPolicy.DeviceOwnerAuthentication, 100));
        Assert.All(later, space => Assert.False(space.Settings.RequiresAuthentication));
        var tie = Settled(Choosing(primary, SpaceAccessPolicy.Open, 100), Choosing(member, SpaceAccessPolicy.DeviceOwnerAuthentication, 100));
        Assert.All(tie, space => Assert.True(space.Settings.RequiresAuthentication));
    }

    #endregion

    #region Actions - Records

    /// A pin the group shares is one tab, stored in the primary whichever
    /// Sub-Space shows it, and never more than a Space pins. A visit a
    /// Sub-Space's page makes is kept in the primary. With separate pinned
    /// tabs each Sub-Space shows its own again, which stayed stored in it.
    [Fact]
    public void ASharedPinIsOneTabTheprimaryKeepsAndVisitsGoToThePrimary() {
        var (primary, subSpace) = (Fixed(3_200), Fixed(3_201));
        var pins = Enumerable.Range(0, TabPlacement.PinnedCapacity - 1).Select(index => Fixed(3_210 + index)).ToArray();
        var (first, second, hidden) = (Fixed(3_230), Fixed(3_231), Fixed(3_232));
        using var device = new TestDevice(SessionOf(
            SpaceOf(primary, Fixed(3_290), "Work", tabs: [.. pins.Select(pin => TabOf(pin, placement: "pinned"))]),
            Joined(SpaceOf(subSpace, Fixed(3_291), "Client",
                tabs: [TabOf(first), TabOf(second), TabOf(hidden, placement: "pinned")]), primary, Fixed(3_290), at: 100)));
        var window = device.Open(subSpace, (subSpace, first));
        IReadOnlyList<Guid> Pinned(Guid space) =>
            [.. device.Authority.Current.Space(space)!.Tabs.Where(tab => tab.Placement == TabPlacement.Pinned).Select(tab => tab.Id)];

        device.Send(new TogglePin(device.Workspace, subSpace, first));
        Assert.Equal([.. pins, first], Pinned(primary));
        Assert.Equal([hidden], Pinned(subSpace));
        Assert.DoesNotContain(device.Authority.Current.Space(subSpace)!.Tabs, tab => tab.Id == first);
        Assert.Equal(first, device.Tab(window, subSpace));
        Assert.IsType<PinnedTabsFull>(Assert.Throws<Rejected>(() =>
            device.Send(new TogglePin(device.Workspace, subSpace, second))).Rejection);

        device.Send(new ShowTab(window, subSpace, pins[0]));
        Assert.Equal(pins[0], device.Tab(window, subSpace));
        var visit = DateTimeOffset.Parse("2026-10-25T12:00:00Z");
        device.Authority.Apply(new NavigationRecord(Guid.NewGuid(), subSpace, visit, second, "https://example.com/visited", "Visited", null,
            Guid.NewGuid()));
        Assert.Contains(device.Authority.Current.Space(primary)!.History, entry => entry.Url == "https://example.com/visited");
        Assert.Empty(device.Authority.Current.Space(subSpace)!.History);

        device.Send(new SetSeparatePinnedTabs(device.Workspace, subSpace, Separates: true));
        Assert.True(device.Authority.Current.Space(primary)!.Settings.SeparatesPinnedTabs);
        Assert.NotEqual(pins[0], device.Tab(window, subSpace));
        device.Send(new TogglePin(device.Workspace, subSpace, second));
        Assert.Equal([hidden, second], Pinned(subSpace));
        Assert.Equal([.. pins, first], Pinned(primary));
    }

    /// Deleting the primary of a locked group takes the group unlocked, while
    /// a locked Sub-Space may go as before. The Sub-Space chosen to lead takes
    /// the session, the primary's pins ahead of its own up to what a Space
    /// pins, and the primary's history made again in it; the other Sub-Spaces
    /// follow it, and no profile any of them browses with is erased.
    [Fact]
    public void APrimaryHandsItsGroupAndRecordsToTheSubSpaceChosenToLeadIt() {
        var (primary, follower, successor, leaving) = (Fixed(3_300), Fixed(3_301), Fixed(3_302), Fixed(3_303));
        var groupProfile = Fixed(3_390);
        var primaryPins = Enumerable.Range(0, 8).Select(index => Fixed(3_310 + index)).ToArray();
        var successorPins = Enumerable.Range(0, 6).Select(index => Fixed(3_320 + index)).ToArray();
        var shared = SpaceOf(primary, groupProfile, "Work", tabs: [.. primaryPins.Select(pin => TabOf(pin, placement: "pinned"))]);
        shared["history"] = new JsonArray(VisitOf(Fixed(3_340), "a", last: 30), VisitOf(Fixed(3_341), "b", last: 40, count: 2));
        var leader = SpaceOf(successor, Fixed(3_392), "Client B",
            tabs: [.. successorPins.Select(pin => TabOf(pin, placement: "pinned")), TabOf(Fixed(3_330))]);
        leader["history"] = new JsonArray(VisitOf(Fixed(3_342), "b", first: 5, last: 20));
        using var device = new TestDevice(SessionOf(Locked(shared),
            Locked(Joined(SpaceOf(follower, Fixed(3_391), "Client A", tabs: [TabOf(Fixed(3_331))]), primary, groupProfile, at: 100)),
            Locked(Joined(leader, primary, groupProfile, at: 100)),
            Locked(Joined(SpaceOf(leaving, Fixed(3_393), "Client C", tabs: [TabOf(Fixed(3_332))]), primary, groupProfile, at: 100))));
        BeginDeletingSpace Deleting(Guid space, Guid? successorId = null) =>
            new(device.Workspace, Guid.NewGuid(), space, Guid.NewGuid(), successorId);

        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Send(Deleting(primary, successor))).Rejection);
        device.Send(Deleting(leaving));
        Assert.Equal([Fixed(3_393)], device.Authority.Current.PendingDeletion(leaving)!.Erasing);
        Unlock(device.Send, device.Workspace, primary);
        Assert.IsType<InvalidNewPrimary>(Assert.Throws<Rejected>(() => device.Send(Deleting(primary, leaving))).Rejection);
        device.Send(Deleting(primary, successor));

        var session = device.Authority.Current;
        var (led, followed, gone) = (session.Space(successor)!, session.Space(follower)!, session.Space(primary)!);
        Assert.Null(led.PrimaryId);
        Assert.Equal(groupProfile, led.ProfileId);
        Assert.Equal(successor, followed.PrimaryId);
        Assert.Equal(groupProfile, followed.ProfileId);
        Assert.Equal([.. primaryPins, .. successorPins[..4]],
            led.Tabs.Where(tab => tab.Placement == TabPlacement.Pinned).Select(tab => tab.Id));
        Assert.Equal(successorPins[4..], led.Tabs.Where(tab => tab.Placement == TabPlacement.Saved).Select(tab => tab.Id));
        Assert.DoesNotContain(gone.Tabs, tab => tab.Placement == TabPlacement.Pinned);
        Assert.Equal(["https://example.com/b", "https://example.com/a"], led.History.Select(entry => entry.Url));
        Assert.Equal((Fixed(3_342), 3), (led.History[0].Id, led.History[0].VisitCount));
        Assert.DoesNotContain(led.History[1].Id, new[] { Fixed(3_340), Fixed(3_341) });
        var deletion = session.PendingDeletion(primary)!;
        Assert.Equal(successor, deletion.SuccessorId);
        Assert.Empty(deletion.Erasing);
        Assert.Null(SessionIdentities.Flaw(session));
    }

    #endregion

    #region Actions - Private windows

    /// A private window's Space is a fresh session every time, which no
    /// Space joins and none is added to.
    [Fact]
    public void APrivateWindowsSpaceNeverShares() {
        using var device = new TestDevice(OneSpaceSession(), WorkspaceKind.Private);
        var space = device.Authority.Current.Spaces[0].Id;

        Assert.IsType<PrivateSpaceCannotShare>(Assert.Throws<Rejected>(() =>
            device.Send(new AddSubSpace(device.Workspace, Guid.NewGuid(), Guid.NewGuid(), space))).Rejection);
        Assert.IsType<PrivateSpaceCannotShare>(Assert.Throws<Rejected>(() =>
            device.Send(new JoinSpace(device.Workspace, space, space))).Rejection);
    }

    #endregion

    #region Actions - Fixtures

    /// `space`, a Space in the stored format, asking the device owner first,
    /// as someone chose 100 seconds after 1970.
    private static JsonObject Locked(JsonObject space) {
        space["accessPolicy"] = "deviceOwnerAuthentication";
        space["accessPolicyModifiedAt"] = At(100);
        return space;
    }

    #endregion
}
