using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the link-navigation and history policy operations. They
/// match the native navigation models' case names.
internal static class NavigationCodes {
    #region Actions - Decoding

    public static LinkPeekModifier PeekModifier(string value) => value switch {
        "option" => LinkPeekModifier.Option,
        "command" => LinkPeekModifier.Command,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPeekModifier)
    };

    #endregion

    #region Actions - Encoding

    public static string Decision(LinkNavigationDecision decision) => decision switch {
        LinkNavigationDecision.PeekModifier => "peekModifier",
        LinkNavigationDecision.PeekSavedSite => "peekSavedSite",
        LinkNavigationDecision.BackgroundTab => "backgroundTab",
        LinkNavigationDecision.ForegroundTab => "foregroundTab",
        _ => "navigate"
    };

    public static JsonObject LinkAnswer(LinkNavigationDecision decision) => new() { ["decision"] = Decision(decision) };

    public static JsonObject HistoryAnswer(string? url) => new() { ["url"] = url };

    #endregion
}
