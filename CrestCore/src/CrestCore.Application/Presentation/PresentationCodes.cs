using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the page presentation and branding policy operations.
/// They match the native presentation models' case names.
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

    public static JsonObject BrandingAnswer(JsonNode branding) => new() { ["branding"] = branding };


    #endregion
}
