using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the Quick Window policy operations. Placements are
/// `{"url","spaceID","profileID"}`; the archive policy uses its persisted
/// native spelling, such as `after6Hours`.
internal static class QuickWindowCodes {
    #region Actions - Decoding

    public static QuickWindowArchivePolicy ArchivePolicy(JsonElement value) => value.GetString() switch {
        "after1Hour" => QuickWindowArchivePolicy.After1Hour,
        "after6Hours" => QuickWindowArchivePolicy.After6Hours,
        "after12Hours" => QuickWindowArchivePolicy.After12Hours,
        "after24Hours" => QuickWindowArchivePolicy.After24Hours,
        "never" => QuickWindowArchivePolicy.Never,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidArchivePolicy)
    };

    public static QuickWindowPlacement Placement(JsonElement value) {
        Protocol.Members(value, "url", "spaceID", "profileID");
        return new(Protocol.Text(value, "url"), Protocol.Id(value, "spaceID"), Protocol.Id(value, "profileID"));
    }

    #endregion

    #region Actions - Encoding

    public static JsonObject LifetimeAnswer(double? lifetime) => new() { ["lifetime"] = lifetime };

    public static JsonObject DismissalAnswer(bool archives) => new() { ["archives"] = archives };

    public static JsonObject RetargetAnswer(QuickWindowRetarget retarget) =>
        new() { ["revises"] = retarget.Revises, ["remembersSpace"] = retarget.RemembersSpace };

    #endregion
}
