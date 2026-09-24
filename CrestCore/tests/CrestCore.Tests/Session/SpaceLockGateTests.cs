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
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
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
        // A locked Space must not even be named as an import destination.
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "workspace.import",
            ["mode"] = "manual",
            ["now"] = 800000002.0,
            ["arguments"] = new JsonObject {
                ["sources"] = new JsonArray(session["spaces"]![0]!.DeepClone()),
                ["drafts"] = new JsonArray(new JsonObject {
                    ["sourceIndex"] = 0,
                    ["isNew"] = false,
                    ["customization"] = new JsonObject {
                        ["name"] = "Reading",
                        ["symbol"] = "book",
                        ["accent"] = "indigo",
                        ["branding"] = new JsonObject()
                    }
                })
            }
        }))).Code);

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

    [Fact]
    public void SyncMaterializationAndDeletionStillReachALockedSpaceWhileItsCommandsStayRejected() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        // Materialized records commit as a session replacement, never as a
        // command, so background convergence does not need a grant.
        using (var reserved = core.ReserveReplacement(RenameDelta(session, "Merged from another device")))
            reserved.Commit();
        Assert.Equal(2UL, core.Revision);
        core.Commit(RenameDelta(session, "Merged again"));
        Assert.Equal(3UL, core.Revision);
        var current = JsonNode.Parse(core.Checkpoint().Read("core"))!;
        Assert.Equal("Merged again", current["spaces"]![0]!["tabs"]![0]!["title"]!.GetValue<string>());
        var deleting = Identity(session).Space;
        device.Send(new BeginDeletingSpace(device.Workspace, Guid.NewGuid(), deleting, Guid.NewGuid()));
        Assert.Equal(deleting, Assert.IsType<SpaceBeingDeleted>(Assert.Throws<Rejected>(() =>
            device.Send(new CleanUpCurrentTabs(device.Workspace, deleting))).Rejection).SpaceId);
    }

    private static byte[] SpaceTabDelta(JsonNode session, int index, string title) {
        var space = session["spaces"]![index]!;
        var tab = space["tabs"]![0]!.DeepClone(); tab["title"] = title;
        return Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject {
                ["id"] = space["id"]!.DeepClone(),
                ["tabs"] = new JsonObject { ["remove"] = new JsonArray(), ["upsert"] = new JsonArray(tab) }
            })
        });
    }

    private static byte[] AccessPolicyDelta(JsonNode session, string policy) {
        var metadata = session["spaces"]![0]!.DeepClone(); metadata["accessPolicy"] = policy;
        return Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject {
                ["id"] = session["spaces"]![0]!["id"]!.DeepClone(),
                ["metadata"] = metadata
            })
        });
    }

    [Fact]
    public void ALockedSpacesRecordsRejectANativeValueEditWhileOtherSpacesAndSyncKeepWriting() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var access = new SpaceAccessAuthority();
        var core = new NativeSessionAuthority(Bytes(session));
        core.AttachAccess(access);
        var identity = Identity(session);
        // A value edit proposes records instead of naming an operation, so the
        // gate reads what the delta would actually change.
        foreach (var attempt in new Action[] {
            () => core.Commit(SpaceTabDelta(session, 0, "Leaked"), nativeValueEdit: true),
            () => core.ReserveReplacement(SpaceTabDelta(session, 0, "Leaked"), nativeValueEdit: true)
        }) Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(attempt).Code);
        // Removing protection is the decision authentication guards, whether it
        // arrives as a command or as a proposed record.
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(
            () => core.Commit(AccessPolicyDelta(session, "open"), nativeValueEdit: true)).Code);
        Assert.Equal(1UL, core.Revision);

        // The unlocked Space in the same session stays editable, and raising
        // protection further on the locked one is allowed as it is for commands.
        core.Commit(SpaceTabDelta(session, 1, "Second space tab"), nativeValueEdit: true);
        core.Commit(AccessPolicyDelta(session, "futureStrongerPolicy"), nativeValueEdit: true);
        Assert.Equal(3UL, core.Revision);

        // Sync materialization commits as a journal-bound replacement rather
        // than a value edit, so background convergence is still unaffected.
        var current = JsonNode.Parse(core.Checkpoint().Read("core"))!;
        core.Commit(SpaceTabDelta(current, 0, "Merged from another device"));
        Assert.Equal(4UL, core.Revision);

        Grant(access, identity);
        current = JsonNode.Parse(core.Checkpoint().Read("core"))!;
        core.Commit(SpaceTabDelta(current, 0, "Mine again"), nativeValueEdit: true);
        Assert.Equal(5UL, core.Revision);
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
        var owner = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(owner);
        var identity = Identity(session);
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(
            () => owner.CreateBorrowed(identity.Space, identity.Profile)).Code);
        Unlock(device.Send, device.Workspace, identity.Space);
        var child = owner.CreateBorrowed(identity.Space, identity.Profile);
        // The borrowed workspace inherits the same authority, so relocking the
        // source also stops edits inside the Blank Window that borrowed it.
        device.Send(new LockSpace(identity.Space));
        var borrowed = device.Attach(child);
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Send(new MoveTab(borrowed, identity.Space,
            Guid.Parse(session["spaces"]![0]!["tabs"]![0]!["id"]!["rawValue"]!.GetValue<string>()), TabPlacement.Current, null, null,
            LeavesSplit: false))).Rejection);
    }

    [Fact]
    public void TwoSpacesCannotShareOneProfileThroughRestore_CommitOrImport() {
        var session = SavedSession().Document["session"]!;
        var space = session["spaces"]![0]!;
        var second = space.DeepClone(); second["id"] = SwiftId(Guid.NewGuid());
        second["tabs"] = new JsonArray(); second["folders"] = new JsonArray();
        second["history"] = new JsonArray(); second["archivedTabs"] = new JsonArray();
        var shared = session.DeepClone();
        shared["spaces"] = new JsonArray(space.DeepClone(), second.DeepClone());
        Assert.Equal("duplicate_space_profile", Assert.Throws<BrowserRuleException>(
            () => new NativeSessionAuthority(Bytes(shared))).Code);

        var core = new NativeSessionAuthority(Bytes(session));
        var metadata = second.DeepClone();
        Assert.Equal("duplicate_space_profile", Assert.Throws<BrowserRuleException>(() => core.Commit(Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject {
                ["id"] = second["id"]!.DeepClone(),
                ["metadata"] = metadata,
                ["tabs"] = new JsonObject { ["replace"] = new JsonArray() }
            }),
            ["spaceOrder"] = new JsonArray(space["id"]!.DeepClone(), second["id"]!.DeepClone())
        }))).Code);
        Assert.Equal(1UL, core.Revision);

        // Repair keeps the first occurrence and issues the collision a fresh
        // profile, so an imported archive cannot adopt another Space's data.
        var repaired = NativeSessionMaintenance.Repair(shared.AsObject(), 800000002.0)["session"]!;
        var profiles = repaired["spaces"]!.AsArray()
            .Select(s => s!["profile"]!["id"]!.GetValue<string>().ToUpperInvariant()).ToArray();
        Assert.Equal(2, profiles.Distinct().Count());
        Assert.Equal(space["profile"]!["id"]!.GetValue<string>().ToUpperInvariant(), profiles[0]);
    }
}
