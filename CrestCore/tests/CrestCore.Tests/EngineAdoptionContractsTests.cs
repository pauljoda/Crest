using System.Text.Json.Nodes;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    [Fact]
    public void NativeAdoptionPreservesExistingNavigationAndRejectsReusedIdentity()
    {
        var (core, window, spaceId) = Kernel(); var space = core.Workspace.Space(spaceId);
        var create = Open(core, window, spaceId);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var token = Guid.NewGuid();
        JsonObject request = new() {
            ["adoptionId"] = token.ToString(), ["profileId"] = space.ProfileId.Value.ToString(),
            ["sourcePageId"] = create.Payload["pageId"]!.GetValue<string>(), ["url"] = "https://example.org/popup", ["foreground"] = true
        };
        var adoption = core.Process(Message("engine.adoption_requested", request, "engine"))
            .Single(o => o.Type == "engine.adopt_page");
        Assert.Equal(token.ToString(), adoption.Payload["adoptionId"]!.GetValue<string>());
        Assert.Equal(2, space.Tabs.Count);
        var completion = core.Process(Message("engine.page_created", Observation(adoption), "engine", adoption.Id, adoption.CorrelationId));
        Assert.DoesNotContain(completion, o => o.Type is "engine.navigate" or "engine.create_page");
        Assert.Equal("https://example.org/popup", space.Tabs.Single(t => t.Id == core.Workspace.Window(window).Selection(spaceId)).Url);
        Assert.Contains(core.Process(Message("engine.adoption_requested", request, "engine")), o => o.Type == "engine.reject_adoption");
        Assert.Equal(2, space.Tabs.Count);
    }
    [Fact]
    public void AdoptionCannotCrossProfilesOrCreateWorkDuringShutdown()
    {
        var (core, window, spaceId) = Kernel(); var create = Open(core, window, spaceId);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var other = core.Workspace.Spaces.Single(s => s.Id != spaceId);
        JsonObject request = new() {
            ["adoptionId"] = Guid.NewGuid().ToString(), ["profileId"] = other.ProfileId.Value.ToString(),
            ["sourcePageId"] = create.Payload["pageId"]!.GetValue<string>(), ["url"] = "https://example.org/popup", ["foreground"] = true
        };
        var refused = core.Process(Message("engine.adoption_requested", request, "engine"));
        Assert.Contains(refused, o => o.Type == "engine.reject_adoption"); Assert.Empty(other.Tabs);
        request["profileId"] = core.Workspace.Space(spaceId).ProfileId.Value.ToString();
        core.BeginShutdown();
        Assert.Contains(core.Process(Message("engine.adoption_requested", request, "engine")), o => o.Type == "engine.reject_adoption");
        Assert.Single(core.Workspace.Space(spaceId).Tabs);
    }
    [Fact]
    public void EngineInitiatedCloseUpdatesCoreArchiveAndCannotUseAStalePageIdentity()
    {
        var (core, window, spaceId) = Kernel(); var create = Open(core, window, spaceId);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var observed = core.Process(Message("engine.page_destroyed", Observation(create), "engine"));
        Assert.Empty(core.Workspace.Space(spaceId).Tabs); Assert.Single(core.Workspace.Space(spaceId).Archive);
        Assert.DoesNotContain(observed, o => o.Type == "engine.close_page");
        Assert.Contains(core.Process(Message("engine.page_destroyed", Observation(create), "engine")), o => o.Type == "core.operation_failed");
        Assert.Single(core.Workspace.Space(spaceId).Archive);
    }
    [Theory]
    [InlineData("chrome://extensions")]
    [InlineData("chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html")]
    public void InternalNavigationRequiresTheEngineCapability(string url)
    {
        Assert.Throws<BrowserRuleException>(() => BrowserWorkspace.ValidateUrl(url));
        BrowserWorkspace.ValidateUrl(url, allowsInternalPages: true);
        Assert.Throws<BrowserRuleException>(() => BrowserWorkspace.ValidateUrl("javascript:alert(1)", allowsInternalPages: true));
        Assert.Throws<BrowserRuleException>(() => BrowserWorkspace.ValidateUrl("chrome-extension://not-an-extension/options", allowsInternalPages: true));
    }
}
