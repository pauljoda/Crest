using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the Quick Window policy operations. Placements are
/// `{"url","spaceID","profileID"}`.
internal static class QuickWindowCodes {
    #region Actions - Decoding

    public static QuickWindowPlacement Placement(JsonElement value) {
        Protocol.Members(value, "url", "spaceID", "profileID");
        return new(Protocol.Text(value, "url"), Protocol.Id(value, "spaceID"), Protocol.Id(value, "profileID"));
    }

    #endregion

    #region Actions - Encoding

    public static JsonObject DismissalAnswer(bool archives) => new() { ["archives"] = archives };

    public static JsonObject RetargetAnswer(QuickWindowRetarget retarget) =>
        new() { ["revises"] = retarget.Revises, ["remembersSpace"] = retarget.RemembersSpace };

    #endregion
}
