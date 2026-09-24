using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.NavigationPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Navigation

    /// Null when the operation is not a link-navigation or history policy.
    private static JsonObject? EvaluateNavigation(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.NavigationLink => Navigate(Requests.Link.Decode(request)),
        PolicyOperation.NavigationModifiedLink => Navigate(Requests.Link.DecodeModified(request)),
        PolicyOperation.HistoryNormalize => new() { ["url"] = HistoryPolicy.Normalize(Requests.HistoryNormalize.Decode(request).Url) },
        _ => null
    };

    private static JsonObject Navigate(Requests.Link link) => new() {
        ["decision"] = LinkNavigationPolicy.Decide(link.Url, link.UserActivatedLink, link.TopLevel, link.PeekModified,
            link.NewTabModified, link.ShiftModified, link.FocusesNewTabs, link.HasContext, link.Placement, link.SavedUrl,
            link.AutomaticallyOpensPeek).Name
    };

    #endregion
}
