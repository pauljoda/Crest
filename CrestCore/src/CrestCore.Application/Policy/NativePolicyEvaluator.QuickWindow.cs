using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Actions - Quick Window

    /// Null when the operation is not a Quick Window policy. Placements are
    /// `{"url","spaceID","profileID"}`; the archive policy uses its persisted
    /// native spelling, such as `after6Hours`.
    private static JsonObject? EvaluateQuickWindow(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.QuickWindowArchiveLifetime:
                Protocol.Members(request, "version", "operation", "policy");
                return new() { ["lifetime"] = QuickWindowPolicy.ArchiveLifetime(ArchivePolicy(request.GetProperty("policy"))) };
            case PolicyOperation.QuickWindowDismissal:
                Protocol.Members(request, "version", "operation", "wasArchived", "wasPromoted", "hasPage");
                return new() {
                    ["archives"] = QuickWindowPolicy.ArchivesOnDismissal(request.GetProperty("wasArchived").GetBoolean(),
                        request.GetProperty("wasPromoted").GetBoolean(), request.GetProperty("hasPage").GetBoolean())
                };
            case PolicyOperation.QuickWindowRetarget:
                Protocol.Members(request, "version", "operation", "current", "next", "pageURL");
                var retarget = QuickWindowPolicy.Retarget(Placement(request.GetProperty("current")),
                    Placement(request.GetProperty("next")), Protocol.OptionalText(request, "pageURL"));
                return new() { ["revises"] = retarget.Revises, ["remembersSpace"] = retarget.RemembersSpace };
            default:
                return null;
        }
    }

    private static QuickWindowArchivePolicy ArchivePolicy(JsonElement value) => value.GetString() switch {
        "after1Hour" => QuickWindowArchivePolicy.After1Hour,
        "after6Hours" => QuickWindowArchivePolicy.After6Hours,
        "after12Hours" => QuickWindowArchivePolicy.After12Hours,
        "after24Hours" => QuickWindowArchivePolicy.After24Hours,
        "never" => QuickWindowArchivePolicy.Never,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidArchivePolicy)
    };

    private static QuickWindowPlacement Placement(JsonElement value) {
        Protocol.Members(value, "url", "spaceID", "profileID");
        return new(Protocol.Text(value, "url"), Protocol.Id(value, "spaceID"), Protocol.Id(value, "profileID"));
    }

    #endregion
}
