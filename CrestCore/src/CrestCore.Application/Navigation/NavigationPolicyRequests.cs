using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the link-navigation and history policy operations.
internal static class NavigationPolicyRequests {
    #region Actions - Decoding

    /// A link activation, reduced to the modifier meaning the person chose:
    /// `navigation.link` reports it directly, `navigation.modified_link`
    /// reports raw keys and the person's peek-modifier preference.
    public sealed record Link(string? Url, bool UserActivatedLink, bool TopLevel, bool PeekModified, bool NewTabModified,
        bool ShiftModified, bool FocusesNewTabs, bool HasContext, TabPlacement? Placement, string? SavedUrl,
        bool AutomaticallyOpensPeek) {
        public static Link Decode(JsonElement request) {
            Members(request, "url", "userActivatedLink", "topLevel", "peekModified", "newTabModified", "shiftModified",
                "focusesNewTabs", "hasContext", "placement", "savedUrl", "automaticallyOpensPeek");
            bool peek = Flag(request, "peekModified");
            bool newTab = Flag(request, "newTabModified");
            return Facts(request, peek, newTab);
        }

        public static Link DecodeModified(JsonElement request) {
            Members(request, "url", "userActivatedLink", "topLevel", "commandModified", "optionModified", "middleClick",
                "peekModifier", "shiftModified", "focusesNewTabs", "hasContext", "placement", "savedUrl",
                "automaticallyOpensPeek");
            var preference = NavigationCodes.PeekModifier(Protocol.Text(request, "peekModifier"));
            var (peek, newTab) = LinkNavigationPolicy.Modifiers(Flag(request, "commandModified"),
                Flag(request, "optionModified"), Flag(request, "middleClick"), preference);
            return Facts(request, peek, newTab);
        }

        private static Link Facts(JsonElement request, bool peek, bool newTab) {
            var url = Element(request, "url").GetString();
            bool userActivated = Flag(request, "userActivatedLink"), topLevel = Flag(request, "topLevel");
            bool shift = Flag(request, "shiftModified"), focuses = Flag(request, "focusesNewTabs"),
                hasContext = Flag(request, "hasContext");
            var placement = TabPlacementCodes.Parse(Element(request, "placement").GetString());
            var savedUrl = Element(request, "savedUrl").GetString();
            return new(url, userActivated, topLevel, peek, newTab, shift, focuses, hasContext, placement, savedUrl,
                Flag(request, "automaticallyOpensPeek"));
        }
    }

    public sealed record HistoryNormalize(string Url) {
        public static HistoryNormalize Decode(JsonElement request) {
            Members(request, "url");
            return new(Protocol.Text(request, "url"));
        }
    }

    #endregion
}
