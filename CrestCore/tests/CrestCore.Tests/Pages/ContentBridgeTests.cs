using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed class ContentBridgeTests {
    [Fact]
    public void EveryContentBridgeLoadsCanonicalJavaScriptFromCore() {
        using var app = new CrestApp(new(StorageDirectory: null, Platform: DevicePlatform.Desktop));

        foreach (var bridge in ContentBridge.All) {
            var script = app.Query(new ContentBridgeSource(bridge, IncludeTestingHooks: false));

            Assert.False(string.IsNullOrWhiteSpace(script.Source));
            Assert.Equal(bridge.HandlerName, script.HandlerName);
            Assert.Equal(bridge.MainFrameOnly, script.MainFrameOnly);
            Assert.DoesNotContain("/*__CREST_TESTING_HOOKS__*/", script.Source, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void CredentialsBridgeSplicesTestingHooksOnlyWhenRequested() {
        using var app = new CrestApp(new(StorageDirectory: null, Platform: DevicePlatform.Desktop));

        var release = app.Query(new ContentBridgeSource(ContentBridge.Credentials, IncludeTestingHooks: false));
        var debug = app.Query(new ContentBridgeSource(ContentBridge.Credentials, IncludeTestingHooks: true));

        Assert.DoesNotContain("inspectForTesting", release.Source, StringComparison.Ordinal);
        Assert.Contains("inspectForTesting", debug.Source, StringComparison.Ordinal);
        Assert.Contains("captureForTesting", debug.Source, StringComparison.Ordinal);
        Assert.Contains("focusForTesting", debug.Source, StringComparison.Ordinal);
    }
}
