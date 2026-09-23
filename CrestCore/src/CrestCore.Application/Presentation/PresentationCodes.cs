using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the page presentation, content-blocking and branding
/// policy operations. They match the native presentation models' case names.
internal static class PresentationCodes {
    #region Actions - Decoding

    public static PagePresentationSelection Selection(JsonElement value) => value.GetString() switch {
        "none" => PagePresentationSelection.None,
        "startPage" => PagePresentationSelection.StartPage,
        "nativeContent" => PagePresentationSelection.NativeContent,
        "webPage" => PagePresentationSelection.WebPage,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPagePresentation)
    };

    public static PageUnloadedBehavior UnloadedBehavior(JsonElement value) => value.GetString() switch {
        "remainUnloaded" => PageUnloadedBehavior.RemainUnloaded,
        "restoreAutomatically" => PageUnloadedBehavior.RestoreAutomatically,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPagePresentation)
    };

    #endregion

    #region Actions - Encoding

    public static string Presentation(PagePresentation value) => value switch {
        PagePresentation.NoSelection => "noSelection",
        PagePresentation.StartPage => "startPage",
        PagePresentation.NativeContent => "nativeContent",
        PagePresentation.LivePage => "livePage",
        PagePresentation.NavigationFailure => "navigationFailure",
        PagePresentation.ProcessFailure => "processFailure",
        PagePresentation.Unloaded => "unloaded",
        _ => "automaticRestore"
    };

    public static JsonObject PresentationAnswer(PagePresentation value) => new() { ["presentation"] = Presentation(value) };

    /// Balanced protection's rules under their store identifier.
    public static JsonObject ContentBlockingAnswer() =>
        new() { ["identifier"] = BalancedContentBlocking.Identifier, ["source"] = BalancedRuleSource() };

    public static JsonObject BrandingAnswer(JsonNode branding) => new() { ["branding"] = branding };

    /// WebKit content-rule JSON for Balanced protection, as the source text the
    /// rule-list store compiles under `BalancedContentBlocking.Identifier`.
    private static string BalancedRuleSource() => new JsonArray(BalancedContentBlocking.BlockedHostSuffixes.Select(host =>
        (JsonNode)new JsonObject {
            ["trigger"] = new JsonObject {
                ["url-filter"] = BalancedContentBlocking.UrlFilter(host),
                ["url-filter-is-case-sensitive"] = true,
                ["load-type"] = new JsonArray("third-party"),
                ["resource-type"] = new JsonArray(BalancedContentBlocking.NetworkResourceTypes
                    .Select(type => (JsonNode?)JsonValue.Create(type)).ToArray())
            },
            ["action"] = new JsonObject { ["type"] = "block" }
        }).ToArray()).ToJsonString();

    #endregion
}
