using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    internal static readonly StoredSpellings<SpaceAccessPolicy> SpaceAccessPolicies = new([
        (SpaceAccessPolicy.Open, "open"), (SpaceAccessPolicy.DeviceOwnerAuthentication, "deviceOwnerAuthentication")
    ]);

    /// What a Space stored without a name or symbol shows.
    private const string FallbackSpaceName = "Space";
    private const string FallbackSpaceSymbol = "square.grid.2x2.fill";

    #endregion

    #region Actions - Spaces

    /// A Space. An accent this build cannot name is indigo, missing preferences
    /// are the defaults, and a Space without an access policy is open while one
    /// whose policy this build cannot name asks for authentication.
    internal static SpaceState DecodeSpace(JsonNode? node) {
        var value = Object(node);
        return new(Identity(value[Key.Id]), Identity(value[Key.Profile]?[Key.Id]),
            new(Text(value[Key.Name]) ?? FallbackSpaceName, Text(value[Key.Symbol]) ?? FallbackSpaceSymbol,
                DecodeAccent(value[Key.Accent]),
                value[Key.Branding] is JsonObject branding ? DecodeBranding(branding) : null,
                value[Key.BrowsingPreferences] is JsonObject browsing ? DecodeBrowsingPreferences(browsing) : DefaultBrowsingPreferences,
                value[Key.CredentialPreferences] is JsonObject credentials
                    ? DecodeCredentialPreferences(credentials) : DefaultCredentialPreferences,
                DecodeAccessPolicy(value[Key.AccessPolicy]),
                Flag(value[Key.IsSavedTabsExpanded]) ?? true,
                OptionalDate(value[Key.SavedTabsExpansionModifiedAt]),
                OptionalDate(value[Key.CredentialsEnabledModifiedAt]),
                OptionalDate(value[Key.AccessPolicyModifiedAt]),
                Flag(value[Key.SeparatesPinnedTabs]) ?? false,
                OptionalDate(value[Key.SeparatesPinnedTabsModifiedAt]),
                OptionalDate(value[Key.ProtectionModifiedAt])),
            [.. Items(value[Key.Folders]).Select(DecodeFolder)],
            [.. Items(value[Key.Tabs]).Select(DecodeTab)],
            [.. Items(value[Key.SplitGroups]).Select(DecodeSplitGroup)],
            [.. Items(value[Key.ArchivedTabs]).Select(DecodeArchivedTab)],
            [.. Items(value[Key.History]).Select(DecodeHistoryEntry)],
            DecodeMembership(value));
    }

    /// A Space's membership, or null for a Space that never joined a group:
    /// one stored without a time is as good as none.
    private static SpaceMembership? DecodeMembership(JsonObject value) => OptionalDate(value[Key.MembershipModifiedAt]) is { } modifiedAt
        ? new(OptionalIdentity(value[Key.PrimarySpaceId]), OptionalIdentity(value[Key.SharedProfileId]), modifiedAt) : null;

    internal static JsonObject Encode(SpaceState space) {
        var settings = space.Settings;
        var value = new JsonObject {
            [Key.Id] = WrappedIdentity(space.Id),
            [Key.Profile] = new JsonObject { [Key.Id] = BareIdentity(space.OwnProfileId) },
            [Key.Name] = settings.Name,
            [Key.Symbol] = settings.Symbol,
            [Key.Accent] = settings.Accent.Name
        };
        if (settings.Branding is { } branding) value[Key.Branding] = Encode(branding);
        value[Key.Folders] = EncodeAll(space.Folders, Encode);
        value[Key.Tabs] = EncodeAll(space.Tabs, Encode);
        value[Key.SplitGroups] = EncodeAll(space.SplitGroups, Encode);
        value[Key.ArchivedTabs] = EncodeAll(space.ArchivedTabs, Encode);
        value[Key.History] = EncodeHistory(space.History);
        value[Key.BrowsingPreferences] = Encode(settings.BrowsingPreferences);
        value[Key.CredentialPreferences] = Encode(settings.CredentialPreferences);
        value[Key.AccessPolicy] = SpaceAccessPolicies.Name(settings.AccessPolicy);
        value[Key.IsSavedTabsExpanded] = settings.IsSavedTabsExpanded;
        Put(value, Key.SavedTabsExpansionModifiedAt, settings.SavedTabsExpansionModifiedAt);
        Put(value, Key.CredentialsEnabledModifiedAt, settings.CredentialsEnabledModifiedAt);
        Put(value, Key.AccessPolicyModifiedAt, settings.AccessPolicyModifiedAt);
        if (settings.SeparatesPinnedTabs) value[Key.SeparatesPinnedTabs] = true;
        Put(value, Key.SeparatesPinnedTabsModifiedAt, settings.SeparatesPinnedTabsModifiedAt);
        Put(value, Key.ProtectionModifiedAt, settings.ProtectionModifiedAt);
        if (space.Membership is { } membership) {
            if (membership.PrimaryId is { } primary) value[Key.PrimarySpaceId] = WrappedIdentity(primary);
            if (membership.SharedProfileId is { } profile) value[Key.SharedProfileId] = BareIdentity(profile);
            Put(value, Key.MembershipModifiedAt, membership.ModifiedAt);
        }
        return value;
    }

    internal static JsonArray EncodeHistory(IEnumerable<HistoryEntryState> history) => EncodeAll(history, Encode);

    /// A stored accent; one this build cannot name is indigo.
    internal static SpaceAccent DecodeAccent(JsonNode? node) => SpaceAccent.Named(TolerantText(node)) ?? SpaceAccent.Indigo;

    /// A stored access policy. None is open; a policy this build cannot name was
    /// somebody restricting the Space, so it resolves to the guarded side.
    internal static SpaceAccessPolicy DecodeAccessPolicy(JsonNode? node) => TolerantText(node) is { } spelling
        ? SpaceAccessPolicies.Parse(spelling) ?? SpaceAccessPolicy.DeviceOwnerAuthentication : SpaceAccessPolicy.Open;

    /// An access policy a command names, or null when this build cannot name it.
    internal static SpaceAccessPolicy? ParseAccessPolicy(string? spelling) => SpaceAccessPolicies.Parse(spelling);

    #endregion

    #region Actions - Session

    /// A session; unlike its other members, its Spaces are never optional.
    internal static SessionState DecodeSession(JsonNode? node) {
        var value = Object(node);
        var spaces = value[Key.Spaces] as JsonArray ?? throw new BrowserRuleException(BrowserRule.InvalidSavedState);
        return new([.. spaces.Select(DecodeSpace)],
            OptionalIdentity(value[Key.DefaultSpaceId]), OptionalIdentity(value[Key.DisposableSeedMarker]),
            DecodeSpaceDeletions(value[Key.SpaceDeletions]) ?? [],
            value[Key.AppPreferences] is JsonObject preferences ? DecodeAppPreferences(preferences) : null);
    }

    internal static JsonObject Encode(SessionState session) {
        var value = new JsonObject { [Key.Spaces] = EncodeAll(session.Spaces, Encode) };
        if (session.DefaultSpaceId is { } defaultSpace) value[Key.DefaultSpaceId] = WrappedIdentity(defaultSpace);
        if (session.DisposableSeedMarker is { } marker) value[Key.DisposableSeedMarker] = BareIdentity(marker);
        if (session.SpaceDeletions.Count > 0) value[Key.SpaceDeletions] = EncodeAll(session.SpaceDeletions, Encode);
        if (session.AppPreferences is { } preferences) value[Key.AppPreferences] = Encode(preferences);
        return value;
    }

    /// The Space deletions a session stores, or null when it stores none.
    internal static IReadOnlyList<SpaceDeletionState>? DecodeSpaceDeletions(JsonNode? node) => node switch {
        null => null,
        JsonArray intents => [.. intents.Select(intent => intent is JsonObject value
            ? new SpaceDeletionState(Identity(value[Key.OperationId]), Identity(value[Key.SpaceId]), Identity(value[Key.ProfileId]),
                value[Key.ErasedProfileIds] is JsonArray erased ? [.. erased.Select(Identity)] : null,
                value[Key.SuccessorSpaceId] is { } successor ? Identity(successor) : null)
            : throw new BrowserRuleException(BrowserRule.InvalidDeletionIntent))],
        _ => throw new BrowserRuleException(BrowserRule.InvalidDeletionIntent)
    };

    internal static JsonObject Encode(SpaceDeletionState deletion) {
        var value = new JsonObject {
            [Key.SpaceId] = WrappedIdentity(deletion.SpaceId),
            [Key.ProfileId] = BareIdentity(deletion.ProfileId),
            [Key.OperationId] = BareIdentity(deletion.Id)
        };
        if (deletion.ErasedProfileIds is { } erased)
            value[Key.ErasedProfileIds] = new JsonArray([.. erased.Select(profile => (JsonNode?)BareIdentity(profile))]);
        if (deletion.SuccessorId is { } successor) value[Key.SuccessorSpaceId] = BareIdentity(successor);
        return value;
    }

    private static JsonArray EncodeAll<T>(IEnumerable<T> records, Func<T, JsonObject> encode) =>
        new(records.Select(record => (JsonNode?)encode(record)).ToArray());

    #endregion
}
