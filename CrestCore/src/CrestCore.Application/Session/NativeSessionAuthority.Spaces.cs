using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Spaces

    private static bool SameDeletionIntent(JsonNode left, JsonNode right) =>
        Id(left["spaceID"]) == Id(right["spaceID"]) && Id(left["profileID"]) == Id(right["profileID"])
        && Id(left["operationID"]) == Id(right["operationID"]);

    private static bool EqualDeletionIntents(JsonNode? left, JsonNode? right) {
        if (left is not null and not JsonArray || right is not null and not JsonArray)
            throw new BrowserRuleException(BrowserRuleCodes.InvalidDeletionIntent);
        var a = left as JsonArray ?? new(); var b = right as JsonArray ?? new();
        // Swift and .NET format UUID casing differently; identity is a UUID,
        // not the spelling chosen by the platform's encoder.
        return a.Count == b.Count && a.All(x => b.Any(y => SameDeletionIntent(x!, y!)));
    }

    private static JsonArray Deletions(JsonObject metadata) => metadata["spaceDeletions"] as JsonArray ?? new();

    private static JsonNode? PendingDeletion(JsonObject metadata, Guid id)
        => Deletions(metadata).FirstOrDefault(d => Id(d!["spaceID"]) == id);

    private NativeSessionCommand PrepareSpaceCommand(ulong expected, JsonObject request) {
        SpaceOrganizationPolicy.RequireOwnedProfiles(workspaceKind);
        var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
        var args = request["arguments"]!.AsObject();
        var window = request["window"]!;
        var selection = window["selectedTabs"]!.AsArray().ToDictionary(n => Id(n!["spaceID"]), n => n!["tabID"]);
        var metadata = document.Metadata.DeepClone().AsObject();
        metadata["selectedSpaceID"] = window["selectedSpaceID"]!.DeepClone();
        var spaces = document.Spaces.Select(s => {
            var fields = s.Metadata.DeepClone().AsObject();
            fields["selectedTabID"] = selection.GetValueOrDefault(Id(fields["id"]))?.DeepClone();
            return new SpaceDocument(fields, s.Sections);
        }).ToList();
        Guid? created = null;
        if (operation is SessionOperation.SpaceCreate or SessionOperation.SpaceResetPrivate) {
            if (operation == SessionOperation.SpaceResetPrivate) {
                if (workspaceKind != BrowserWorkspaceKind.Private) throw new BrowserRuleException(BrowserRuleCodes.NotPrivateWorkspace);
                var fresh = args["template"]!;
                if (spaces.Any(s => Id(s.Metadata["id"]) == Id(fresh["id"])
                    || Id(s.Metadata["profile"]!["id"]) == Id(fresh["profile"]!["id"])))
                    throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
                spaces.Clear();
                metadata.Remove("spaceDeletions"); metadata.Remove("defaultSpaceID");
            }
            var supplied = args["template"]!.AsObject();
            var id = Id(supplied["id"]);
            var profile = Id(supplied["profile"]!["id"]);
            if (spaces.Any(s => Id(s.Metadata["id"]) == id || Id(s.Metadata["profile"]!["id"]) == profile))
                throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
            var fields = Fields(supplied, Sections);
            fields["name"] = operation == SessionOperation.SpaceResetPrivate ? "Private" :
                (workspaceKind == BrowserWorkspaceKind.Private ? "Private " : "Space ") + (spaces.Count + 1);
            var sections = Sections.ToDictionary(section => section,
                section => (IReadOnlyList<JsonNode>)supplied[section]!.AsArray().Select(n => n!.DeepClone()).ToArray());
            if (sections["history"].Count != 0 || sections["archivedTabs"].Count != 0 || sections["folders"].Count != 0
                || sections["tabs"].Count != 1 || sections["tabs"][0]["url"] is not null)
                throw new BrowserRuleException(BrowserRuleCodes.InvalidNewSpace);
            if (workspaceKind == BrowserWorkspaceKind.Private) {
                fields["symbol"] = "eyeglasses";
                fields["accent"] = SpaceAccentCodes.Indigo;
                var browsing = fields["browsingPreferences"]!.AsObject();
                browsing["selectedSearchProviderID"] = "duckDuckGo";
                browsing["searchProvider"] = "duckDuckGo";
                browsing["currentTabCleanupPolicy"] = "never";
                fields["credentialPreferences"] = new JsonObject {
                    ["isEnabled"] = false,
                    ["syncsCrestPasswordsWithICloud"] = false,
                    ["alsoOffersSaveToSystemPasswords"] = false
                };
            }
            spaces.Add(new(fields, sections));
            metadata["selectedSpaceID"] = supplied["id"]!.DeepClone();
            created = id;
        } else if (operation == SessionOperation.SpaceReorder) {
            spaces = SpaceOrganizationPolicy.Move(spaces,
                args["offsets"]!.AsArray().Select(n => n!.GetValue<int>()), args["destination"]!.GetValue<int>()).ToList();
        } else {
            var id = Id(request["spaceId"]);
            var index = spaces.FindIndex(s => Id(s.Metadata["id"]) == id);
            if (index < 0) throw new BrowserRuleException(BrowserRuleCodes.UnknownSpace);
            var space = spaces[index];
            if (Id(request["profileId"]) != Id(space.Metadata["profile"]!["id"]))
                throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
            var fields = space.Metadata;
            var pending = PendingDeletion(metadata, id);
            if (pending is not null && operation is not (SessionOperation.SpaceDeletionBegin or SessionOperation.SpaceRemove))
                throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
            switch (operation) {
                case SessionOperation.SpaceDeletionBegin:
                    var operationId = Id(args["operationID"]);
                    if (pending is not null) {
                        if (Id(pending["operationID"]) != operationId)
                            throw new BrowserRuleException(BrowserRuleCodes.WrongDeletionOperation);
                        break;
                    }
                    SpaceOrganizationPolicy.RequireRemovable(spaces.Count - Deletions(metadata).Count);
                    var deletions = Deletions(metadata);
                    if (metadata["spaceDeletions"] is null) metadata["spaceDeletions"] = deletions;
                    deletions.Add((JsonNode)new JsonObject {
                        ["spaceID"] = fields["id"]!.DeepClone(),
                        ["profileID"] = fields["profile"]!["id"]!.DeepClone(),
                        ["operationID"] = operationId.ToString("D")
                    });
                    if (Id(metadata["selectedSpaceID"]) == id)
                        metadata["selectedSpaceID"] = spaces.First(s => PendingDeletion(metadata, Id(s.Metadata["id"])) is null)
                            .Metadata["id"]!.DeepClone();
                    break;
                case SessionOperation.SpaceIdentity:
                    fields["name"] = SpaceOrganizationPolicy.Name(args["name"]!.GetValue<string>());
                    fields["symbol"] = SpaceOrganizationPolicy.Symbol(args["symbol"]!.GetValue<string>());
                    var accent = args["accent"]!.GetValue<string>();
                    if (!SpaceAccentCodes.Includes(accent)) throw new BrowserRuleException(BrowserRuleCodes.InvalidAccent);
                    fields["accent"] = accent;
                    break;
                case SessionOperation.SpaceBranding:
                    // The native view supplies its rendering vocabulary. Store it
                    // as metadata without reconstructing tabs, history or images.
                    fields["branding"] = args["value"]!.AsObject().DeepClone();
                    break;
                case SessionOperation.SpaceBrowsingPreferences:
                    fields["browsingPreferences"] = args["value"]!.AsObject().DeepClone();
                    break;
                case SessionOperation.SpaceSearchProviderUpsert or SessionOperation.SpaceSearchProviderRemove:
                    EditSearchProviders(operation, fields, args);
                    break;
                case SessionOperation.SpaceCredentialPreferences:
                    fields["credentialPreferences"] = args["value"]!.AsObject().DeepClone();
                    break;
                case SessionOperation.SpaceAccess:
                    var access = args["value"]!.GetValue<string>();
                    if (access is not (SpaceAccessPolicyCodes.Open or SpaceAccessPolicyCodes.DeviceOwnerAuthentication))
                        throw new BrowserRuleException(BrowserRuleCodes.InvalidAccessPolicy);
                    fields["accessPolicy"] = access;
                    break;
                case SessionOperation.SpaceDefault:
                    metadata["defaultSpaceID"] = fields["id"]!.DeepClone();
                    break;
                case SessionOperation.SpaceSavedExpansion:
                    var expanded = args["value"]!.GetValue<bool>();
                    if (fields["isSavedTabsExpanded"]?.GetValue<bool>() != expanded) {
                        fields["isSavedTabsExpanded"] = expanded;
                        fields["savedTabsExpansionModifiedAt"] = request["now"]!.DeepClone();
                    }
                    break;
                case SessionOperation.SpaceRemove:
                    if (pending is null || Id(pending["operationID"]) != Id(args["operationID"]))
                        throw new BrowserRuleException(BrowserRuleCodes.WrongDeletionOperation);
                    SpaceOrganizationPolicy.RequireRemovable(spaces.Count);
                    spaces.RemoveAt(index);
                    Deletions(metadata).Remove(pending);
                    if (Deletions(metadata).Count == 0) metadata.Remove("spaceDeletions");
                    if (Id(metadata["selectedSpaceID"]) == id)
                        metadata["selectedSpaceID"] = spaces[Math.Min(index, spaces.Count - 1)].Metadata["id"]!.DeepClone();
                    if (metadata["defaultSpaceID"] is { } defaultId && Id(defaultId) == id)
                        metadata["defaultSpaceID"] = metadata["selectedSpaceID"]!.DeepClone();
                    break;
                default: throw new BrowserRuleException(BrowserRuleCodes.UnknownSpaceCommand);
            }
        }
        var next = new SessionDocument(metadata, spaces);
        Validate(next);
        var projection = metadata.DeepClone().AsObject();
        projection["spaces"] = new JsonArray(spaces.Select(s => {
            var value = s.Metadata.DeepClone().AsObject();
            foreach (var section in Sections)
                value[section] = new JsonArray(created == Id(s.Metadata["id"])
                    ? s.Sections[section].Select(n => n.DeepClone()).ToArray() : []);
            return (JsonNode)value;
        }).ToArray());
        var output = Encoding.UTF8.GetBytes(new JsonObject { ["session"] = projection }.ToJsonString());
        if (output.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        return new NativeSessionCommand(this, expected, next, output);
    }

    #endregion
}
