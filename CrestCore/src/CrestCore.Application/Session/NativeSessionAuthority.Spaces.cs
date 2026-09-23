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
        var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
        BorrowedCommandRouting.RequireLocal(operation, workspaceKind == BrowserWorkspaceKind.Temporary);
        var args = request["arguments"]!.AsObject();
        var view = SessionView.Decode(request[SessionView.Key]);
        var hint = new SessionSelectionHint();
        var metadata = document.Metadata.DeepClone().AsObject();
        var spaces = document.Spaces.Select(s => s with { Metadata = s.Metadata.DeepClone().AsObject() }).ToList();
        Guid? created = null;
        if (operation is SessionOperation.SpaceCreate or SessionOperation.SpaceResetPrivate) {
            if (operation == SessionOperation.SpaceResetPrivate) {
                if (workspaceKind != BrowserWorkspaceKind.Private) throw new BrowserRuleException(BrowserRuleCodes.NotPrivateWorkspace);
                var fresh = args["template"]!;
                if (spaces.Any(s => s.Id == Id(fresh["id"]) || s.ProfileId == Id(fresh["profile"]!["id"])))
                    throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
                spaces.Clear();
                metadata.Remove("spaceDeletions"); metadata.Remove("defaultSpaceID");
            }
            var template = StoredSessionCodec.DecodeSpace(args["template"]!.AsObject());
            var id = template.Id;
            if (spaces.Any(s => s.Id == id || s.ProfileId == template.ProfileId))
                throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
            var fields = template.Metadata;
            fields["name"] = operation == SessionOperation.SpaceResetPrivate ? "Private" :
                (workspaceKind == BrowserWorkspaceKind.Private ? "Private " : "Space ") + (spaces.Count + 1);
            if (template.History.Count != 0 || template.ArchivedTabs.Count != 0 || template.Folders.Count != 0
                || template.Tabs.Count != 1 || template.Tabs[0].Url is not null)
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
            spaces.Add(template with { Metadata = fields });
            // A new Space is the one its window shows next, on its only tab.
            hint.SelectSpace(id).SelectTab(view, id, template.Tabs[0].Id);
            created = id;
        } else if (operation == SessionOperation.SpaceReorder) {
            spaces = SpaceOrganizationPolicy.Move(spaces,
                args["offsets"]!.AsArray().Select(n => n!.GetValue<int>()), args["destination"]!.GetValue<int>()).ToList();
        } else {
            var id = Id(request["spaceId"]);
            var index = spaces.FindIndex(s => s.Id == id);
            if (index < 0) throw new BrowserRuleException(BrowserRuleCodes.UnknownSpace);
            var space = spaces[index];
            if (Id(request["profileId"]) != space.ProfileId)
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
                    // The window showing a Space that is going away moves to the
                    // first one that stays.
                    if (view.SpaceId == id)
                        hint.SelectSpace(spaces.First(s => PendingDeletion(metadata, s.Id) is null).Id);
                    break;
                case SessionOperation.SpaceIdentity:
                    fields["name"] = SpaceOrganizationPolicy.Name(args["name"]!.GetValue<string>());
                    fields["symbol"] = SpaceOrganizationPolicy.Symbol(args["symbol"]!.GetValue<string>());
                    var accent = args["accent"]!.GetValue<string>();
                    if (!SpaceAccentCodes.Includes(accent)) throw new BrowserRuleException(BrowserRuleCodes.InvalidAccent);
                    fields["accent"] = accent;
                    break;
                case SessionOperation.SpaceBranding:
                    // The native view supplies its rendering vocabulary. The core
                    // applies its range rules and stores the rest as metadata.
                    fields["branding"] = BrandingDocument.Normalize(args["value"]!.AsObject());
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
                    // The Space that takes the removed one's place is where its
                    // window goes and, when it was the launch Space, the new one.
                    var neighbor = spaces[Math.Min(index, spaces.Count - 1)].Id;
                    if (view.SpaceId == id) hint.SelectSpace(neighbor);
                    if (metadata["defaultSpaceID"] is { } defaultId && Id(defaultId) == id)
                        metadata["defaultSpaceID"] = StoredSessionCodec.WrappedIdentity(neighbor);
                    break;
                default: throw new BrowserRuleException(BrowserRuleCodes.UnknownSpaceCommand);
            }
        }
        var next = new SessionDocument(metadata, spaces);
        Validate(next);
        var projection = StoredSessionCodec.Encode(next with {
            Spaces = spaces.Select(s => created == s.Id ? s : Settings(s)).ToArray()
        });
        return new NativeSessionCommand(this, expected, next, Output(new JsonObject {
            ["session"] = projection,
            [SessionSelectionHint.Key] = hint.Encode()
        }));
    }

    #endregion
}
