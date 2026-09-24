using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonObject EngineDescriptor(string implementation = "test.webkit", string role = "engine") => new() {
        ["adapterId"] = "engine",
        ["role"] = role,
        ["implementationId"] = implementation,
        ["implementationVersion"] = "1",
        ["protocolVersion"] = 1,
        ["capabilities"] = new JsonObject {
            ["pages"] = Declared(),
            ["navigation"] = Declared(),
            ["workspace-profiles"] = Declared(),
            ["profile-deletion"] = Declared(),
            ["pdf"] = Declared("unavailable"),
            ["extensions"] = Declared("unverified")
        }
    };
    private static JsonObject Declared(string status = "supported") => new() {
        ["status"] = status,
        ["contractVersion"] = 1,
        ["scope"] = "Native test port",
        ["limitations"] = new JsonArray(),
        ["evidence"] = "Contract test"
    };

    [Fact]
    public void EngineRegistrationIsLocalAndDoesNotTravelWithRestoredBrowserState() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        authority.RegisterEngine(Bytes(EngineDescriptor()));
        Assert.True(authority.Engine!.Supports(EngineCapability.Navigation));
        Assert.False(authority.Engine.Supports(EngineCapability.Pdf));
        Assert.False(authority.Engine.Supports(EngineCapability.Extensions));
        Assert.False(authority.Engine.Supports(EngineCapability.Find));
        Assert.Equal(1UL, authority.Revision);
        authority.Commit(1, RenameDelta(session, "Engine-independent tab"));
        var saved = authority.Checkpoint(2).Read("core");
        Assert.DoesNotContain("test.webkit", System.Text.Encoding.UTF8.GetString(saved));
        var restored = new NativeSessionAuthority(saved);
        Assert.Null(restored.Engine);
        restored.RegisterEngine(Bytes(EngineDescriptor("test.chromium")));
        Assert.Equal("test.chromium", restored.Engine!.Implementation);
        Assert.Equal("test.webkit", authority.Engine.Implementation);
        Assert.Equal(saved, restored.Checkpoint(1).Read("core"));
    }

    [Fact]
    public void EngineRegistrationRejectsWrongRolesUnknownNavigationVersionsAndReplacement() {
        var authority = new NativeSessionAuthority(Bytes(SavedSession().Document["session"]!));
        Assert.Throws<BrowserRuleException>(() => authority.RegisterEngine(Bytes(EngineDescriptor(role: "services"))));
        var descriptor = EngineDescriptor();
        descriptor["capabilities"]!["navigation"]!["contractVersion"] = 2;
        Assert.Throws<BrowserRuleException>(() => authority.RegisterEngine(Bytes(descriptor)));
        descriptor["capabilities"]!["navigation"]!["contractVersion"] = 1;
        descriptor["capabilities"]!["navigation"]!["status"] = "unverified";
        Assert.Throws<BrowserRuleException>(() => authority.RegisterEngine(Bytes(descriptor)));
        descriptor = EngineDescriptor();
        descriptor["capabilities"]!.AsObject().Remove("workspace-profiles");
        Assert.Throws<BrowserRuleException>(() => authority.RegisterEngine(Bytes(descriptor)));
        Assert.Null(authority.Engine);
        authority.RegisterEngine(Bytes(EngineDescriptor()));
        Assert.Throws<BrowserRuleException>(() => authority.RegisterEngine(Bytes(EngineDescriptor("test.other"))));
        Assert.Equal("test.webkit", authority.Engine!.Implementation);
    }
}
