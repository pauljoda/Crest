using System.Text.Json.Nodes;

using CrestCore.Application;
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
    private static void Grant(SpaceAccessAuthority access, SpaceAccessAssignment identity)
        => Assert.True(access.Complete(access.Begin(identity, true), identity, true));

    [Fact]
    public void LockedSpaceCommandsAreRejectedBeforePreparationUntilAGrantExistsAndAgainAfterRelocking() {
        var session = GuardedSession();
        var access = new SpaceAccessAuthority();
        var core = new NativeSessionAuthority(Bytes(session));
        core.AttachAccess(access);
        var identity = Identity(session);
        var rename = SpaceCommand(session, "tab.rename", new() { ["tabId"] = session["spaces"]![0]!["tabs"]![0]!["id"]!["rawValue"]!.DeepClone(), ["title"] = "Leaked" });
        var folder = SpaceCommand(session, "folder.rename", new() { ["folderId"] = session["spaces"]![0]!["folders"]![0]!["id"]!["rawValue"]!.DeepClone(), ["title"] = "Leaked" });
        var visit = SpaceCommand(session, "history.visit",
            new() { ["url"] = "https://example.com/secret", ["title"] = "Secret" });
        foreach (var request in new[] { rename, folder, visit })
            Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(1, request)).Code);
        Assert.Equal(1UL, core.Revision);
        // A locked Space must not even be named as an import destination.
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(1, Bytes(new JsonObject {
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

        Grant(access, identity);
        core.PrepareCommand(1, rename).Commit();
        Assert.Equal(2UL, core.Revision);

        access.Lock(identity.Space);
        var current = JsonNode.Parse(core.Checkpoint(2).Read("core"))!;
        var relocked = JsonNode.Parse(SpaceCommand(current, "tab.rename", new() { ["tabId"] = current["spaces"]![0]!["tabs"]![0]!["id"]!["rawValue"]!.DeepClone(), ["title"] = "After relock" }))!;
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(
            () => core.PrepareCommand(2, Bytes(relocked))).Code);
        // Taking protection away is the decision authentication guards.
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(
            2, SpaceCommand(current, "space.access", new() { ["value"] = "open" }))).Code);
        // Raising it, and retention maintenance, must still reach a locked
        // Space: neither returns its contents to the caller.
        core.PrepareCommand(2, SpaceCommand(current, "space.access",
            new() { ["value"] = "deviceOwnerAuthentication" })).Commit();
        core.PrepareCommand(3, SpaceCommand(current, "records.sweep", new())).Commit();
        Grant(access, identity);
        core.PrepareCommand(4, Bytes(relocked)).Commit();
    }

    [Fact]
    public void SyncMaterializationAndDeletionStillReachALockedSpaceWhileItsCommandsStayRejected() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var access = new SpaceAccessAuthority();
        var core = new NativeSessionAuthority(Bytes(session));
        core.AttachAccess(access);
        // Materialized records commit as a session replacement, never as a
        // command, so background convergence does not need a grant.
        using (var reserved = core.ReserveReplacement(1, RenameDelta(session, "Merged from another device")))
            Assert.Equal(2UL, reserved.Commit());
        core.Commit(2, RenameDelta(session, "Merged again"));
        Assert.Equal(3UL, core.Revision);
        var current = JsonNode.Parse(core.Checkpoint(3).Read("core"))!;
        Assert.Equal("Merged again", current["spaces"]![0]!["tabs"]![0]!["title"]!.GetValue<string>());
        var operation = Guid.NewGuid().ToString();
        core.PrepareCommand(3, SpaceCommand(current, "space.deletion.begin",
            new() { ["operationID"] = operation })).Commit();
        Assert.Equal("space_deletion_in_progress", Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(
            4, SpaceCommand(current, "records.cleanup", new()))).Code);
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
        foreach (var attempt in new Func<object>[] {
            () => core.Commit(1, SpaceTabDelta(session, 0, "Leaked"), nativeValueEdit: true),
            () => core.ReserveReplacement(1, SpaceTabDelta(session, 0, "Leaked"), nativeValueEdit: true)
        }) Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(() => attempt()).Code);
        // Removing protection is the decision authentication guards, whether it
        // arrives as a command or as a proposed record.
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(
            () => core.Commit(1, AccessPolicyDelta(session, "open"), nativeValueEdit: true)).Code);
        Assert.Equal(1UL, core.Revision);

        // The unlocked Space in the same session stays editable, and raising
        // protection further on the locked one is allowed as it is for commands.
        core.Commit(1, SpaceTabDelta(session, 1, "Second space tab"), nativeValueEdit: true);
        core.Commit(2, AccessPolicyDelta(session, "futureStrongerPolicy"), nativeValueEdit: true);
        Assert.Equal(3UL, core.Revision);

        // Sync materialization commits as a journal-bound replacement rather
        // than a value edit, so background convergence is still unaffected.
        var current = JsonNode.Parse(core.Checkpoint(3).Read("core"))!;
        core.Commit(3, SpaceTabDelta(current, 0, "Merged from another device"));
        Assert.Equal(4UL, core.Revision);

        Grant(access, identity);
        current = JsonNode.Parse(core.Checkpoint(4).Read("core"))!;
        core.Commit(4, SpaceTabDelta(current, 0, "Mine again"), nativeValueEdit: true);
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
        var access = new SpaceAccessAuthority();
        var owner = new NativeSessionAuthority(Bytes(session));
        owner.AttachAccess(access);
        var identity = Identity(session);
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(
            () => owner.CreateBorrowed(1, identity.Space, identity.Profile)).Code);
        Grant(access, identity);
        var child = owner.CreateBorrowed(1, identity.Space, identity.Profile);
        // The borrowed workspace inherits the same authority, so relocking the
        // source also stops edits inside the Blank Window that borrowed it.
        access.Lock(identity.Space);
        var local = JsonNode.Parse(child.PrepareBorrowedRefresh(1).Output)!["session"]!;
        Assert.Equal("space_locked", Assert.Throws<BrowserRuleException>(() => child.PrepareCommand(1, Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "tab.rename",
            ["now"] = 800000100.0,
            ["spaceId"] = local["spaces"]![0]!["id"]!.DeepClone(),
            ["profileId"] = local["spaces"]![0]!["profile"]!["id"]!.DeepClone(),
            ["arguments"] = new JsonObject { ["tabId"] = Guid.NewGuid().ToString(), ["title"] = "Leaked" }
        }))).Code);
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
        Assert.Equal("duplicate_space_profile", Assert.Throws<BrowserRuleException>(() => core.Commit(1, Bytes(new JsonObject {
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
