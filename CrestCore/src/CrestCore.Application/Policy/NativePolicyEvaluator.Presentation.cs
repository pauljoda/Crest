using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Variables

    private const int MaximumBrandingBytes = MaximumInputBytes / 2;

    #endregion

    #region Actions - Presentation

    /// Null when the operation is not a page presentation, content-blocking or
    /// branding policy.
    private static JsonObject? EvaluatePresentation(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.PagePresentation:
                Protocol.Members(request, "version", "operation", "selection", "hasActivePage", "hasNavigationFailure",
                    "hasProcessFailure", "unloadedBehavior");
                var presentation = PagePresentationPolicy.Resolve(PresentationSelection(request.GetProperty("selection")),
                    request.GetProperty("hasActivePage").GetBoolean(), request.GetProperty("hasNavigationFailure").GetBoolean(),
                    request.GetProperty("hasProcessFailure").GetBoolean(), UnloadedBehavior(request.GetProperty("unloadedBehavior")));
                return new() { ["presentation"] = PresentationName(presentation) };
            case PolicyOperation.ContentBlockingRules:
                Protocol.Members(request, "version", "operation");
                return new() { ["identifier"] = BalancedContentBlocking.Identifier, ["source"] = BalancedRuleSource() };
            case PolicyOperation.BrandingNormalize:
                Protocol.Members(request, "version", "operation", "branding");
                var branding = request.GetProperty("branding");
                if (branding.ValueKind != JsonValueKind.Object || branding.GetRawText().Length > MaximumBrandingBytes)
                    throw new ProtocolException(ProtocolErrorCodes.InvalidBranding);
                return new() { ["branding"] = BrandingDocument.Normalize(JsonNode.Parse(branding.GetRawText())!.AsObject()) };
            default:
                return null;
        }
    }

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

    private static PagePresentationSelection PresentationSelection(JsonElement value) => value.GetString() switch {
        "none" => PagePresentationSelection.None,
        "startPage" => PagePresentationSelection.StartPage,
        "nativeContent" => PagePresentationSelection.NativeContent,
        "webPage" => PagePresentationSelection.WebPage,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPagePresentation)
    };

    private static PageUnloadedBehavior UnloadedBehavior(JsonElement value) => value.GetString() switch {
        "remainUnloaded" => PageUnloadedBehavior.RemainUnloaded,
        "restoreAutomatically" => PageUnloadedBehavior.RestoreAutomatically,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPagePresentation)
    };

    private static string PresentationName(PagePresentation value) => value switch {
        PagePresentation.NoSelection => "noSelection",
        PagePresentation.StartPage => "startPage",
        PagePresentation.NativeContent => "nativeContent",
        PagePresentation.LivePage => "livePage",
        PagePresentation.NavigationFailure => "navigationFailure",
        PagePresentation.ProcessFailure => "processFailure",
        PagePresentation.Unloaded => "unloaded",
        _ => "automaticRestore"
    };

    #endregion
}
