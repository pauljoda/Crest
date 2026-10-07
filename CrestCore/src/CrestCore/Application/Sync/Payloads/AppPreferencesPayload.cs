using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The app's synced behavior preferences: what a window opens with, translation
/// and its per-language rules, spelling, automatic Picture in Picture, what
/// closing a saved tab does, whether Split View focus follows the pointer and
/// whether local pages open with the developer toolbar. There is one record for
/// the account, which belongs to no Space and so carries a fixed identity that
/// names itself, and the later write wins whole.
internal sealed record AppPreferencesPayload(AppPreferences Preferences) : SyncPayload {
    #region Static Variables

    /// The one identity every client gives the record.
    public static Guid RecordId { get; } = new("5a1c0b6e-3d6f-4f0a-9c53-a9f05e3c0a01");

    #endregion

    #region Variables

    public override Guid Id => RecordId;

    public override Guid SpaceId => RecordId;
    public override SyncRecordKind Kind => SyncRecordKind.AppPreferences;

    /// Older builds know no record of this kind, so they leave it for a build that does.
    public override int Schema => 4;

    #endregion

    #region Actions - Coding

    /// A value this build cannot read keeps its default, as the stored preferences read.
    public static AppPreferencesPayload Read(SyncPayloadReader value) {
        value.WrappedIdentity("id");
        return new(StoredSessionCodec.DecodeAppPreferences(value.Value));
    }

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject { ["id"] = StoredSessionCodec.WrappedIdentity(Id) };
        foreach (var (key, member) in StoredSessionCodec.Encode(Preferences)) value[key] = member?.DeepClone();
        return value;
    }

    #endregion

    #region Actions - Validation

    public override void Validate() {
        if (Id != RecordId) throw new UnreadableSyncPayloadException();
    }

    #endregion
}
