using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonNode GuardedSession(bool withOpenSecondSpace = false) {
        var session = SavedSession().Document["session"]!;
        session["spaces"]![0]!["accessPolicy"] = "deviceOwnerAuthentication";
        if (withOpenSecondSpace)
            session["spaces"]!.AsArray().Add(SavedSession().Document["session"]!["spaces"]![0]!.DeepClone());
        return session;
    }
    private static SpaceAccessAssignment Identity(JsonNode session) => new(
        Guid.Parse(session["spaces"]![0]!["id"]!["rawValue"]!.GetValue<string>()),
        Guid.Parse(session["spaces"]![0]!["profile"]!["id"]!.GetValue<string>()));
    private static void Grant(SpaceAccessAuthority access, SpaceAccessAssignment identity) {
        var request = Guid.NewGuid();
        Assert.Equal([identity], access.Begin(identity, true, request));
        access.Finish(identity.Space, request, authenticated: true);
    }

    private static void Unlock(Func<Intent, IReadOnlyList<Change>> send, Guid workspace, Guid space) =>
        TestGrants.Unlock(send, workspace, space);

    [Fact]
    public void LockedSpaceCommandsAreRejectedBeforePreparationUntilAGrantExistsAndAgainAfterRelocking() {
        var session = GuardedSession();
        using var device = new TestDevice(session);
        var core = device.Authority;
        var identity = Identity(session);
        var tab = Guid.Parse(session["spaces"]![0]!["tabs"]![0]!["id"]!["rawValue"]!.GetValue<string>());
        var move = new MoveTab(device.Workspace, identity.Space, tab, TabPlacement.Current, null, null, LeavesSplit: false);
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Send(move)).Rejection);
        var folder = Guid.Parse(session["spaces"]![0]!["folders"]![0]!["id"]!["rawValue"]!.GetValue<string>());
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new RenameFolder(device.Workspace, identity.Space, folder, "Leaked"))).Rejection);
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new RenameTab(device.Workspace, identity.Space, tab, "Leaked"))).Rejection);
        Assert.Equal(1UL, core.Revision);
        // A setup that would add tabs to a locked Space and rename it is refused.
        var draft = session["spaces"]![0]!.DeepClone();
        var setup = new ApplyManualSetup(device.Workspace, Guid.NewGuid(), Encoding.UTF8.GetBytes(new JsonArray(draft).ToJsonString()),
            [new(identity.Space, false, new("Renamed", "book", SpaceAccent.Indigo, StoredSessionCodec.DecodeBranding(new JsonObject())))],
            false);
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Send(setup)).Rejection);
        Assert.Equal(1UL, core.Revision);
        // A person sees the setup before they unlock the Space it writes into.
        Assert.Equal("Renamed", device.Query(new ImportPreview(setup)).Session.Spaces[0].Settings.Name);

        Unlock(device.Send, device.Workspace, identity.Space);
        device.Send(new RenameTab(device.Workspace, identity.Space, tab, "Granted"));
        Assert.Equal(2UL, core.Revision);

        device.Send(new LockSpace(identity.Space));
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Send(move)).Rejection);
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new RenameTab(device.Workspace, identity.Space, tab, "After relock"))).Rejection);
        // Taking protection away is the decision authentication guards.
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new SetSpaceAccess(device.Workspace, identity.Space, SpaceAccessPolicy.Open))).Rejection);
        // Raising it, and retention maintenance, must still reach a locked
        // Space: neither returns its contents to the caller. Clearing its
        // history is an edit the grant guards.
        device.Send(new SetSpaceAccess(device.Workspace, identity.Space, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Assert.Equal(identity.Space, Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new ClearHistory(device.Workspace, identity.Space))).Rejection).SpaceId);
        device.Send(new SweepExpiredRecords(device.Workspace));
        device.Send(new CleanUpCurrentTabs(device.Workspace, identity.Space));
        Unlock(device.Send, device.Workspace, identity.Space);
        device.Send(new RenameTab(device.Workspace, identity.Space, tab, "After relock"));
        Assert.Equal("After relock", core.Current.Spaces[0].Tabs[0].CustomTitle);
    }

    /// A Space as the stored format writes it, byte for byte.
    private static string Stored(SpaceState space) => StoredSessionCodec.Encode(space).ToJsonString();

    /// The name and look a Space already has, as a draft left unchanged carries them.
    private static SpaceCustomization OwnCustomization(SpaceState space) =>
        new(space.Settings.Name, space.Settings.Symbol, space.Settings.Accent, space.Settings.Branding!);

    [Fact]
    public void AReviewedImportIsRefusedOnlyWhenItWouldJoinTabsIntoALockedSpace() {
        var session = GuardedSession(withOpenSecondSpace: true).AsObject();
        session.Remove("disposableSeedMarker");
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var locked = device.Authority.Current.Spaces[0];
        var kept = Stored(locked);
        // The core matched "Reading" to the locked Space; "Travel" is new.
        var matched = ImportedSpace("Reading", ImportedTab("https://matched.example/"));
        var fresh = ImportedSpace("Travel", ImportedTab("https://travel.example/"));
        ImportReviewedSpaces Review(bool joinsLocked) => new(device.Workspace, window, ImportedSpaces(matched, fresh), [
            new(SpaceId(matched), joinsLocked, locked.Id, OwnCustomization(locked), [TabId(matched["tabs"]![0]!)], []),
            new(SpaceId(fresh), true, null, Customization("Trips"), [TabId(fresh["tabs"]![0]!)], [])
        ]);

        var before = device.Authority.Current;
        Assert.Equal(new SpaceLocked(locked.Id), Assert.Throws<Rejected>(() => device.Send(Review(joinsLocked: true))).Rejection);
        Assert.Same(before, device.Authority.Current);

        // Left out, the match changes nothing, so the rest imports.
        device.Send(Review(joinsLocked: false));
        var current = device.Authority.Current;
        Assert.Equal(3, current.Spaces.Count);
        Assert.Equal(kept, Stored(current.Spaces[0]));
        Assert.Equal("Trips", current.Spaces[2].Settings.Name);
    }

    [Fact]
    public void AManualSetupIsRefusedOnlyWhenItsDraftWouldChangeALockedSpace() {
        var session = GuardedSession(withOpenSecondSpace: true);
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var (locked, open) = (device.Authority.Current.Spaces[0], device.Authority.Current.Spaces[1]);
        var kept = Stored(locked);
        JsonObject Draft(SpaceState space, params JsonObject[] tabs) {
            var draft = ImportedSpace(space.Settings.Name, tabs);
            draft["id"] = SwiftId(space.Id);
            draft["profile"]!["id"] = space.ProfileId.ToString();
            return draft;
        }
        // Every existing Space is a draft; the open one gains a tab and a name,
        // and the drafts' order moves the locked Space second.
        ApplyManualSetup Setup(SpaceCustomization lockedLook) => new(device.Workspace, window,
            ImportedSpaces(Draft(open, ImportedTab("https://added.example/")), Draft(locked)),
            [new(open.Id, false, Customization("Renamed")), new(locked.Id, false, lockedLook)], OrderWasEdited: true);

        var before = device.Authority.Current;
        Assert.Equal(new SpaceLocked(locked.Id), Assert.Throws<Rejected>(() => device.Send(Setup(Customization("Also renamed")))).Rejection);
        Assert.Same(before, device.Authority.Current);

        // Moving a Space in the order changes no Space, as ReorderSpaces moves a locked one too.
        device.Send(Setup(OwnCustomization(locked)));
        var current = device.Authority.Current;
        Assert.Equal([open.Id, locked.Id], current.Spaces.Select(space => space.Id));
        Assert.Equal(kept, Stored(current.Spaces[1]));
        Assert.Equal("Renamed", current.Spaces[0].Settings.Name);
        Assert.Contains(current.Spaces[0].Tabs, tab => tab.Url == "https://added.example/");
    }

    [Fact]
    public void DeletionStillReachesALockedSpaceWhileItsCommandsStayRejected() {
        var session = GuardedSession(withOpenSecondSpace: true);
        using var device = new TestDevice(session);
        var deleting = Identity(session).Space;
        device.Send(new BeginDeletingSpace(device.Workspace, Guid.NewGuid(), deleting, Guid.NewGuid()));
        Assert.Equal(deleting, Assert.IsType<SpaceBeingDeleted>(Assert.Throws<Rejected>(() =>
            device.Send(new CleanUpCurrentTabs(device.Workspace, deleting))).Rejection).SpaceId);
    }

    private static IReadOnlyList<JsonObject> SpaceRecords(JsonNode session) {
        var space = Guid.Parse(session["spaces"]![0]!["id"]!["rawValue"]!.GetValue<string>());
        return NativeSyncProjection.Project(session.DeepClone().AsObject(), SyncProjectionPreferences(), [])
            .Select(payload => new JsonObject {
                ["id"] = new JsonObject {
                    ["kind"] = payload!["type"]!.DeepClone(),
                    ["value"] = (payload["type"]!.GetValue<string>() == "archive"
                        ? payload["value"]!["tab"]!["id"] : payload["value"]!["id"])!.DeepClone()
                },
                ["spaceID"] = SwiftId(space),
                ["version"] = new JsonObject { ["logicalClock"] = 1, ["deviceID"] = Guid.NewGuid().ToString() },
                ["payload"] = payload.DeepClone()
            }).ToArray();
    }

    [Fact]
    public void SyncCannotRemoveProtectionFromASpaceThisDeviceHasNotUnlocked() {
        var local = GuardedSession();
        var remote = local.DeepClone(); remote["spaces"]![0]!["accessPolicy"] = "open";
        var access = new SpaceAccessAuthority();
        var identity = Identity(local);
        // The policy has no modification stamp of its own, so a stale remote
        // copy would otherwise unlock the Space nobody authenticated for.
        Assert.Equal("deviceOwnerAuthentication", Policy(local, remote, access));
        Grant(access, identity);
        Assert.Equal("open", Policy(local, remote, access));

        // Raising protection never needs a grant, and neither does a device
        // that has attached no authority at all being told to protect a Space.
        var openLocal = local.DeepClone(); openLocal["spaces"]![0]!["accessPolicy"] = "open";
        Assert.Equal("deviceOwnerAuthentication", Policy(openLocal, local, new SpaceAccessAuthority()));
        Assert.Equal("deviceOwnerAuthentication", Policy(openLocal, local, null));
        // With no authority to consult there is no grant, so protection stays.
        Assert.Equal("deviceOwnerAuthentication", Policy(local, remote, null));

        static string? Policy(JsonNode local, JsonNode remote, SpaceAccessAuthority? access)
            => NativeSyncMaterializer.Materialize(local.DeepClone().AsObject(), SyncProjectionPreferences(),
                SpaceRecords(remote), 800000010.0, access)["spaces"]![0]!["accessPolicy"]?.GetValue<string>();
    }

    [Fact]
    public void ALockedSpaceCannotBeBorrowedOrTransferredIntoATemporaryWorkspace() {
        var session = GuardedSession();
        using var device = new TestDevice(session);
        var owner = device.Authority;
        var identity = Identity(session);
        Assert.Equal(new SpaceLocked(identity.Space), Assert.Throws<Rejected>(
            () => device.Send(new BorrowSpace(device.Workspace, identity.Space, identity.Profile))).Rejection);
        Unlock(device.Send, device.Workspace, identity.Space);
        var borrowed = device.Borrow(session["spaces"]![0]!);
        // The borrowed workspace inherits the same authority, so relocking the
        // source also stops edits inside the Blank Window that borrowed it.
        device.Send(new LockSpace(identity.Space));
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Send(new MoveTab(borrowed, identity.Space,
            Guid.Parse(session["spaces"]![0]!["tabs"]![0]!["id"]!["rawValue"]!.GetValue<string>()), TabPlacement.Current, null, null,
            LeavesSplit: false))).Rejection);
    }

    [Fact]
    public void TwoSpacesCannotShareOneProfileThroughRestoreOrImport() {
        var session = SavedSession().Document["session"]!;
        var space = session["spaces"]![0]!;
        var second = space.DeepClone(); second["id"] = SwiftId(Guid.NewGuid());
        second["tabs"] = new JsonArray(); second["folders"] = new JsonArray();
        second["history"] = new JsonArray(); second["archivedTabs"] = new JsonArray();
        var shared = session.DeepClone();
        shared["spaces"] = new JsonArray(space.DeepClone(), second.DeepClone());
        using (var app = new CrestApp())
            Assert.Equal(new InvalidSession(SessionFlaw.SharedProfile), Assert.Throws<Rejected>(
                () => app.Send(new OpenWorkspace(WorkspaceKind.Persistent, TestWorkspaces.Seed(shared)))).Rejection);

        // Repair keeps the first occurrence and issues the collision a fresh
        // profile, so an imported archive cannot adopt another Space's data.
        var repaired = NativeSessionMaintenance.Repair(shared.AsObject(), 800000002.0)["session"]!;
        var profiles = repaired["spaces"]!.AsArray()
            .Select(s => s!["profile"]!["id"]!.GetValue<string>().ToUpperInvariant()).ToArray();
        Assert.Equal(2, profiles.Distinct().Count());
        Assert.Equal(space["profile"]!["id"]!.GetValue<string>().ToUpperInvariant(), profiles[0]);
    }
}
