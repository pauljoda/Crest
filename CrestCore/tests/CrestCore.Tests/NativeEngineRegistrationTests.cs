using System.Text.Json.Nodes;
using CrestCore.Application;
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
            ["pages"] = EngineCapability(),
            ["navigation"] = EngineCapability(),
            ["pdf"] = EngineCapability("unavailable"),
            ["extensions"] = EngineCapability("unverified")
        }
    };
    private static JsonObject EngineCapability(string status = "supported") => new() {
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
        Assert.True(authority.Engine!.Supports("navigation"));
        Assert.False(authority.Engine.Supports("pdf"));
        Assert.False(authority.Engine.Supports("extensions"));
        Assert.False(authority.Engine.Supports("unknown-feature"));
        Assert.Equal(1UL, authority.Revision);
        authority.Commit(1, RenameDelta(session, "Engine-independent tab"));
        var saved = authority.Checkpoint(2, Selection(session)).Read("core");
        Assert.DoesNotContain("test.webkit", System.Text.Encoding.UTF8.GetString(saved));
        var restored = new NativeSessionAuthority(saved);
        Assert.Null(restored.Engine);
        restored.RegisterEngine(Bytes(EngineDescriptor("test.chromium")));
        Assert.Equal("test.chromium", restored.Engine!.Implementation);
        Assert.Equal("test.webkit", authority.Engine.Implementation);
        Assert.Equal(saved, restored.Checkpoint(1, Selection(session)).Read("core"));
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
        Assert.Null(authority.Engine);
        authority.RegisterEngine(Bytes(EngineDescriptor()));
        Assert.Throws<BrowserRuleException>(() => authority.RegisterEngine(Bytes(EngineDescriptor("test.other"))));
        Assert.Equal("test.webkit", authority.Engine!.Implementation);
    }
}
