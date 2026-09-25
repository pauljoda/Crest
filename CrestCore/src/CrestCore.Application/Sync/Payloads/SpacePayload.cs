using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A Space's synced value: its identity and profile, how it looks and
/// browses, who may open it, its saved tabs' disclosure, its splits' metadata
/// and its position among the Spaces.
internal sealed partial record SpacePayload(
    Guid Id,
    Guid ProfileId,
    string Name,
    string Symbol,
    SpaceAccent Accent,
    SpaceBranding Branding,
    BrowsingPreferences BrowsingPreferences,
    SpaceAccessPolicy AccessPolicy,
    bool IsSavedTabsExpanded,
    SyncTime? SavedTabsExpansionModifiedAt,
    IReadOnlyList<SplitGroupPayload>? SplitGroups,
    string OrderToken) : SyncPayload {
    #region Static Variables

    /// The most splits a Space's record names.
    private const int MaximumSplitGroups = 5_000;

    private const int MaximumNameBytes = 128;
    private const int MaximumSymbolBytes = 128;

    #endregion

    #region Variables

    public override Guid Id { get; } = Id;
    public override SyncRecordKind Kind => SyncRecordKind.Space;

    public override Guid SpaceId => Id;

    #endregion

    #region Actions - Coding

    /// The Space `value` holds. A Space without branding wears the branding its
    /// accent and symbol gave it before brandings synced; one without browsing
    /// preferences or an access policy takes the defaults; one without a saved
    /// tabs disclosure shows them; and one without splits' metadata holds no
    /// opinion about any.
    public static SpacePayload Read(SyncPayloadReader value) {
        string name = value.Text("name"), symbol = value.Text("symbol");
        var accent = StoredSessionCodec.ParseAccent(value.Text("accent")) ?? throw new UnreadableSyncPayloadException();
        return new(value.WrappedIdentity("id"), value.Identity("profileID"), name, symbol, accent,
            value.OptionalNested("branding") is { } branding ? ReadBranding(branding) : LegacyBranding(accent, symbol),
            value.OptionalNested("browsingPreferences") is { } browsing ? ReadBrowsingPreferences(browsing)
                : StoredSessionCodec.DefaultBrowsingPreferences,
            value.OptionalText("accessPolicy") is { } access
                ? StoredSessionCodec.ParseAccessPolicy(access) ?? throw new UnreadableSyncPayloadException() : SpaceAccessPolicy.Open,
            value.OptionalFlag("isSavedTabsExpanded") ?? true,
            value.OptionalTime("savedTabsExpansionModifiedAt"),
            value.OptionalArray("splitGroups") is { } groups ? SplitGroupPayload.Normalized(groups, value.Form) : null,
            value.Text("orderToken"));
    }

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject {
            ["id"] = StoredSessionCodec.WrappedIdentity(Id),
            ["profileID"] = StoredSessionCodec.BareIdentity(ProfileId),
            ["name"] = Name,
            ["symbol"] = Symbol,
            ["accent"] = StoredSessionCodec.Spelling(Accent),
            ["branding"] = EncodeBranding(Branding),
            ["browsingPreferences"] = StoredSessionCodec.Encode(BrowsingPreferences),
            ["accessPolicy"] = StoredSessionCodec.SpaceAccessPolicies.Name(AccessPolicy),
            ["isSavedTabsExpanded"] = IsSavedTabsExpanded
        };
        Put(value, "savedTabsExpansionModifiedAt", SavedTabsExpansionModifiedAt, form);
        if (SplitGroups is { } groups) value["splitGroups"] = new JsonArray([.. groups.Select(group => (JsonNode?)group.Encode(form))]);
        value["orderToken"] = OrderToken;
        return value;
    }

    #endregion

    #region Actions - Validation

    public override void Validate() {
        RequireText(Name, MaximumNameBytes);
        RequireText(Symbol, MaximumSymbolBytes);
        if (SplitGroups is { } groups) {
            if (groups.Count > MaximumSplitGroups || groups.Select(group => group.Id).Distinct().Count() != groups.Count)
                throw new UnreadableSyncPayloadException();
            foreach (var group in groups) group.Validate();
        }
        RequireOrderToken(OrderToken);
    }

    #endregion
}
