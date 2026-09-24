using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The core makes new Spaces itself, up to its limit, and deletes one in two
/// saved steps that a relaunch resumes.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void TheCoreMakesEachNewSpaceAndStopsAtTheSpaceLimit() {
        var f = SavedSession(); var session = f.Document["session"]!;
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var window = device.Showing(session);
        var (created, profile, tab) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        device.Ids.Supply([profile, tab]);

        device.Send(new CreateSpace(device.Workspace, window, created));

        // The new Space has the profile and Start Page tab the core gave it,
        // takes the next accent and wears that accent's house palette.
        var space = core.Current.Spaces[^1];
        Assert.Equal((created, profile, "Space 2", SpaceAccent.Orange), (space.Id, space.ProfileId, space.Settings.Name, space.Settings.Accent));
        Assert.Equal(CrestSymbol.Sun, space.Settings.Branding!.Crest.Symbol);
        Assert.Equal((tab, TabPlacement.Current, (string?)null), (Assert.Single(space.Tabs).Id, space.Tabs[0].Placement, space.Tabs[0].Url));
        Assert.Equal(SpaceAccessPolicy.Open, space.Settings.AccessPolicy);
        Assert.Equal((created, tab), (device.Space(window), device.Tab(window, created)));
        Assert.Equal(created, Assert.IsType<SpaceAlreadyExists>(Assert.Throws<Rejected>(() =>
            device.Send(new CreateSpace(device.Workspace, window, created))).Rejection).SpaceId);

        while (core.Current.Spaces.Count < BrowserLimits.Spaces) device.Send(new CreateSpace(device.Workspace, window, Guid.NewGuid()));
        var full = core.Current;
        var another = new CreateSpace(device.Workspace, window, Guid.NewGuid());
        Assert.Equal(BrowserLimits.Spaces, Assert.IsType<SpaceLimitReached>(device.Query(new CanSend(another)).Refusal).Limit);
        Assert.Equal(new SpaceLimitReached(BrowserLimits.Spaces), Assert.Throws<Rejected>(() => device.Send(another)).Rejection);
        Assert.Same(full, core.Current);
    }

    [Fact]
    public void APrivateWorkspaceMakesPrivateSpacesAndStartsOverWithOne() {
        var session = SavedSession().Document["session"]!;
        session["coreWorkspaceKind"] = "private";
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var window = device.Showing(session);

        device.Send(new CreateSpace(device.Workspace, window, Guid.NewGuid()));
        var added = core.Current.Spaces[1];
        Assert.Equal(("Private 2", "eyeglasses", BuiltInSearchEngine.DuckDuckGo, CurrentTabCleanup.Never),
            (added.Settings.Name, added.Settings.Symbol, added.Settings.BrowsingPreferences.SelectedBuiltInEngine,
                added.Settings.BrowsingPreferences.CurrentTabCleanup));
        Assert.Equal(new CredentialPreferences(false, false, false), added.Settings.CredentialPreferences);
        device.Send(new BeginDeletingSpace(device.Workspace, window, added.Id, Guid.NewGuid()));

        device.Send(new ResetPrivateBrowsing(device.Workspace, window));
        var fresh = Assert.Single(core.Current.Spaces);
        Assert.Equal("Private", fresh.Settings.Name);
        Assert.Empty(core.Current.SpaceDeletions);
        Assert.Equal(fresh.Id, device.Space(window));

        var persistent = new NativeSessionAuthority(Bytes(SavedSession().Document["session"]!));
        var ordinary = device.Attach(persistent);
        Assert.Equal(new NotPrivateWorkspace(ordinary), Assert.Throws<Rejected>(() =>
            device.Send(new ResetPrivateBrowsing(ordinary, window))).Rejection);
        var borrowed = device.Attach(core.CreateBorrowed(fresh.Id, fresh.ProfileId));
        Assert.Equal(new BorrowedProfileRequiresOwner(borrowed), Assert.Throws<Rejected>(() =>
            device.Send(new CreateSpace(borrowed, window, Guid.NewGuid()))).Rejection);
    }

    [Fact]
    public void ADeletionIsSavedBeforeItsProfileIsErasedAndARelaunchFinishesIt() {
        var session = SavedSession().Document["session"]!;
        var second = session["spaces"]![0]!.DeepClone();
        second["id"] = SwiftId(Guid.NewGuid()); second["profile"]!["id"] = Guid.NewGuid().ToString();
        second["tabs"] = new JsonArray(); second["selectedTabID"] = null;
        session["spaces"]!.AsArray().Add(second);
        var (first, other) = (SpaceId(session["spaces"]![0]!), SpaceId(second));
        var core = new NativeSessionAuthority(Bytes(session));
        byte[] saved;
        var operation = Guid.NewGuid();
        using (var device = new TestDevice(core)) {
            var window = device.Showing(session);
            device.Send(new BeginDeletingSpace(device.Workspace, window, first, operation));
            // The window leaves the Space being deleted, which takes no edits
            // and refuses another deletion.
            Assert.Equal(other, device.Space(window));
            Assert.Equal(new SpaceBeingDeleted(first), Assert.Throws<Rejected>(() =>
                device.Send(new SetSpaceIdentity(device.Workspace, first, "Revived", "globe", SpaceAccent.Teal))).Rejection);
            Assert.Equal(new WrongDeletionOperation(first), Assert.Throws<Rejected>(() =>
                device.Send(new BeginDeletingSpace(device.Workspace, window, first, Guid.NewGuid()))).Rejection);
            Assert.IsType<CannotDeleteLastSpace>(Assert.Throws<Rejected>(() =>
                device.Send(new BeginDeletingSpace(device.Workspace, window, other, Guid.NewGuid()))).Rejection);
            saved = core.Checkpoint().Read("core");
        }

        // The app quit while the profile's data was being erased.
        var relaunched = new NativeSessionAuthority(saved);
        using var again = new TestDevice(relaunched);
        var shown = again.Open(other);
        Assert.Single(relaunched.Current.SpaceDeletions);
        var resumed = relaunched.Current;
        again.Send(new BeginDeletingSpace(again.Workspace, shown, first, operation));
        Assert.Same(resumed, relaunched.Current);
        Assert.Equal(new WrongDeletionOperation(first), Assert.Throws<Rejected>(() =>
            again.Send(new FinishDeletingSpace(again.Workspace, shown, first, Guid.NewGuid()))).Rejection);

        again.Send(new FinishDeletingSpace(again.Workspace, shown, first, operation));
        // The Space that takes its place is the launch Space and what the window shows.
        Assert.Equal(other, Assert.Single(relaunched.Current.Spaces).Id);
        Assert.Empty(relaunched.Current.SpaceDeletions);
        Assert.Equal(other, relaunched.Current.DefaultSpaceId);
        Assert.Equal(other, again.Space(shown));
        Assert.Equal(new UnknownSpace(first), Assert.Throws<Rejected>(() =>
            again.Send(new FinishDeletingSpace(again.Workspace, shown, first, operation))).Rejection);
    }
}
