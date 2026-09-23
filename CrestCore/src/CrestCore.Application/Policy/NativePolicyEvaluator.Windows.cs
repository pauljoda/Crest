using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

using Requests = CrestCore.Application.WindowPolicyRequests;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Windows

    /// Null when the operation is not a window policy. Window state is
    /// device-local: these operations answer from identities and presence
    /// facts, and the native store applies the answer to its record.
    private static JsonObject? EvaluateWindows(PolicyOperation operation, JsonElement request) => operation switch {
        PolicyOperation.WindowRepair => RepairWindow(Requests.Repair.Decode(request)),
        PolicyOperation.WindowSplitLayout => WindowCodes.SplitLayoutAnswer(
            WindowStatePolicy.SplitFractions(Requests.SplitLayout.Decode(request).Fractions)),
        PolicyOperation.WindowTearOff => TearOff(Requests.TearOff.Decode(request)),
        _ => null
    };

    private static JsonObject RepairWindow(Requests.Repair request) => WindowCodes.RepairAnswer(
        WindowStatePolicy.Repair(request.SelectedSpaceId, request.CapturesSelection, request.Spaces, request.Layouts));

    private static JsonObject TearOff(Requests.TearOff request) => WindowCodes.TearOffAnswer(WindowStatePolicy.AllowsTearOff(
        request.SpaceMatches, request.SpaceLocked, request.ContainsTab, request.SelectionCount, request.SelectionIncludesTab));

    #endregion
}
