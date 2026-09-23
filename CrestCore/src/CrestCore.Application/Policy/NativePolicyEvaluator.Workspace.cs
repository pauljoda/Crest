using System.Text.Json;
using System.Text.Json.Nodes;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Workspace routing

    /// Null when the operation is not a workspace routing policy.
    private static JsonObject? EvaluateWorkspace(PolicyOperation operation, JsonElement request) {
        if (operation != PolicyOperation.WorkspaceCommandRoute) return null;
        var route = WorkspacePolicyCodes.CommandRouteRequest.Decode(request);
        return WorkspacePolicyCodes.RouteAnswer(BorrowedCommandRouting.Route(route.Command, route.Borrowed));
    }

    #endregion
}
