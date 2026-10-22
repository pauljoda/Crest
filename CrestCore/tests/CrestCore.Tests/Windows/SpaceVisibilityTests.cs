using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Which Spaces a device shows is device state: kept beside the session and
/// never synced. A hidden Space stays in the session, but no window shows it
/// and nothing a window offers to switch to names it; at least one Space stays
/// shown, even once the only shown one goes, and only the person's own session
/// hides any.
public sealed partial class BrowserContractsTests {
    private static SpaceVisibility VisibilityIn(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<SpaceVisibilityChanged>()).Visibility;

    [Fact]
    public void HidingASpaceMovesItsWindowsAwayAndSurvivesARelaunch() {
        using var directory = new StorageDirectory();
        var window = Guid.NewGuid();
        Guid first, second;
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            first = SpaceId(spaces[0]!);
            app.Send(new OpenWindow(window, workspace, Saved: true, null, first, [], RestoresTabs: true));
            app.Send(new CreateSpace(workspace, window, Guid.NewGuid()));
            app.Send(new ShowSpace(window, first));
            var others = app.Workspace(workspace).Current.Spaces.Select(space => space.Id).Where(id => id != first).ToList();
            second = others[0];
            Assert.Equal(new SpaceVisibility([]), app.Query(new GetSpaceVisibility()));

            var changes = app.Send(new ShowSpaceOnDevice(first, Shown: false));
            Assert.Equal(new SpaceVisibility([first]), VisibilityIn(changes));
            Assert.Equal(second, changes.OfType<WindowChanged>().Single().Window.ShownSpaceId);
            // The session keeps the Space; only this device leaves it out.
            Assert.Contains(app.Workspace(workspace).Current.Spaces, space => space.Id == first);
            Assert.Empty(app.Send(new ShowSpace(window, first)).OfType<WindowChanged>());
            foreach (var other in others.Skip(1)) app.Send(new ShowSpaceOnDevice(other, Shown: false));
            Assert.IsType<CannotHideLastSpace>(Assert.Throws<Rejected>(() =>
                app.Send(new ShowSpaceOnDevice(second, Shown: false))).Rejection);
            foreach (var other in others.Skip(1)) app.Send(new ShowSpaceOnDevice(other, Shown: true));
            Assert.Equal(new UnknownSpace(Guid.Empty), Assert.Throws<Rejected>(() =>
                app.Send(new ShowSpaceOnDevice(Guid.Empty, Shown: false))).Rejection);
        }

        {
            var (relaunched, workspace, _) = DeviceApp(directory);
            using var disposal = relaunched;
            Assert.Equal(new SpaceVisibility([first]), relaunched.Query(new GetSpaceVisibility()));
            var reopened = Shown(relaunched.Send(new OpenWindow(window, workspace, Saved: true, null, null, [], RestoresTabs: true)));
            Assert.Equal(second, reopened.ShownSpaceId);
            Assert.Equal(new SpaceVisibility([]), VisibilityIn(relaunched.Send(new ShowSpaceOnDevice(first, Shown: true))));
            Assert.Equal(first, Shown(relaunched.Send(new ShowSpace(window, first))).ShownSpaceId);
        }
    }

    [Fact]
    public void AHiddenSpaceIsLeftOutOfEverySpaceAWindowOffersAndForgottenOnceDeleted() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));
        device.Send(new ShowSpaceOnDevice(f.Second, Shown: false));

        Assert.Equal([f.Space, f.Third], device.Query(new NumberedSelections(window)).Selections
            .Where(selection => selection.Target == NumberedSelectionTarget.Space).Select(selection => selection.SpaceId));
        device.Send(new ShowAdjacentSpace(window, AdjacentDirection.Next));
        Assert.Equal(f.Third, device.Space(window));
        Assert.Equal([f.Space, f.Third], device.Query(new DockMenu([window])).Spaces.Select(space => space.SpaceId));
        // A link routed to the hidden Space opens in the one on screen instead.
        var route = Guid.NewGuid();
        device.Send(new AddLinkRoute(route, f.Second));
        device.Send(new EditLinkRoute(route, IsEnabled: null, Match: null, Pattern: "example.com", DestinationSpaceId: null));
        Assert.Equal(f.Third, device.Query(new RouteExternalLink([window], "https://example.com/")).SpaceId);

        // Another workspace shows every Space it holds.
        var other = device.Attach(new OrderSpace().Session, WorkspaceKind.Private);
        var otherWindow = device.OpenIn(other, null);
        Assert.Equal(3, device.Query(new NumberedSelections(otherWindow)).Selections
            .Count(selection => selection.Target == NumberedSelectionTarget.Space));

        var operation = Guid.NewGuid();
        device.Send(new BeginDeletingSpace(device.Workspace, window, f.Second, operation));
        device.Send(new DeleteProfileData(Guid.NewGuid(),
            device.Authority.Current.Spaces.First(space => space.Id == f.Second).ProfileId, Ephemeral: false));
        Assert.Equal(new SpaceVisibility([]),
            VisibilityIn(device.Send(new FinishDeletingSpace(device.Workspace, window, f.Second, operation))));

        // Once the only Space shown goes, every Space shows again.
        device.Send(new ShowSpaceOnDevice(f.Third, Shown: false));
        Assert.Equal(f.Space, device.Space(window));
        Assert.Equal(new SpaceVisibility([]),
            VisibilityIn(device.Send(new BeginDeletingSpace(device.Workspace, window, f.Space, Guid.NewGuid()))));
        Assert.Equal(f.Third, device.Space(window));
    }
}
