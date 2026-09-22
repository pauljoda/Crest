using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Workspace routing

    /// Null when the operation is not a workspace routing policy. Answers which
    /// authority applies a session command: `local`, `source` (the Space a
    /// borrowed workspace borrows from) or `rejected`.
    private static JsonObject? EvaluateWorkspace(PolicyOperation operation, JsonElement request) {
        if (operation != PolicyOperation.WorkspaceCommandRoute) return null;
        Protocol.Members(request, "version", "operation", "command", "borrowed");
        var route = BorrowedCommandRouting.Route(SessionOperationCodes.Parse(Protocol.Text(request, "command", 64)),
            request.GetProperty("borrowed").GetBoolean());
        return new() {
            ["route"] = route switch {
                BorrowedCommandRoute.Source => "source",
                BorrowedCommandRoute.Rejected => "rejected",
                _ => "local"
            }
        };
    }

    #endregion
}
