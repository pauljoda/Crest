using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using static CrestCore.Application.PolicyFields;

namespace CrestCore.Application;

/// Typed requests for the page presentation and branding policy operations.
internal static class PresentationPolicyRequests {
    #region Variables

    private const int MaximumBrandingBytes = NativePolicyEvaluator.MaximumInputBytes / 2;

    #endregion

    #region Actions - Decoding

    public sealed record Page(PagePresentationSelection Selection, bool HasActivePage, bool HasNavigationFailure,
        bool HasProcessFailure, PageUnloadedBehavior UnloadedBehavior) {
        public static Page Decode(JsonElement request) {
            Members(request, "selection", "hasActivePage", "hasNavigationFailure", "hasProcessFailure", "unloadedBehavior");
            var selection = PresentationCodes.Selection(Element(request, "selection"));
            bool active = Flag(request, "hasActivePage"), navigationFailure = Flag(request, "hasNavigationFailure"),
                processFailure = Flag(request, "hasProcessFailure");
            return new(selection, active, navigationFailure, processFailure,
                PresentationCodes.UnloadedBehavior(Element(request, "unloadedBehavior")));
        }
    }

    /// A Space's branding record as native stores it, normalized whole.
    public sealed record Branding(JsonObject Document) {
        public static Branding Decode(JsonElement request) {
            Members(request, "branding");
            var branding = Element(request, "branding");
            if (branding.ValueKind != JsonValueKind.Object || branding.GetRawText().Length > MaximumBrandingBytes)
                throw new ProtocolException(ProtocolErrorCodes.InvalidBranding);
            return new(JsonNode.Parse(branding.GetRawText())!.AsObject());
        }
    }

    #endregion
}
