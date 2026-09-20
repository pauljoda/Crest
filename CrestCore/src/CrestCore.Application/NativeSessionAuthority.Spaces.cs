using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority
{
    private NativeSessionCommand PrepareSpaceCommand(ulong expected, JsonObject request)
    {
        SpaceOrganizationPolicy.RequireOwnedProfiles(workspaceKind);
        var operation = request["operation"]!.GetValue<string>();
        var args = request["arguments"]!.AsObject();
        var window = request["window"]!;
        var selection = window["selectedTabs"]!.AsArray().ToDictionary(n => Id(n!["spaceID"]), n => n!["tabID"]);
        var metadata = document.Metadata.DeepClone().AsObject();
        metadata["selectedSpaceID"] = window["selectedSpaceID"]!.DeepClone();
        var spaces = document.Spaces.Select(s =>
        {
            var fields = s.Metadata.DeepClone().AsObject();
            fields["selectedTabID"] = selection.GetValueOrDefault(Id(fields["id"]))?.DeepClone();
            return new SpaceDocument(fields, s.Sections);
        }).ToList();
        Guid? created = null;
        if (operation == "space.create")
        {
            var supplied = args["template"]!.AsObject();
            var id = Id(supplied["id"]);
            var profile = Id(supplied["profile"]!["id"]);
            if (spaces.Any(s => Id(s.Metadata["id"]) == id || Id(s.Metadata["profile"]!["id"]) == profile))
                throw new BrowserRuleException("duplicate_space_profile");
            var fields = Fields(supplied, Sections);
            fields["name"] = (workspaceKind == BrowserWorkspaceKind.Private ? "Private " : "Space ") + (spaces.Count + 1);
            var sections = Sections.ToDictionary(section => section,
                section => (IReadOnlyList<JsonNode>)supplied[section]!.AsArray().Select(n => n!.DeepClone()).ToArray());
            if (sections["history"].Count != 0 || sections["archivedTabs"].Count != 0 || sections["folders"].Count != 0
                || sections["tabs"].Count != 1 || sections["tabs"][0]["url"] is not null)
                throw new BrowserRuleException("invalid_new_space");
            if (workspaceKind == BrowserWorkspaceKind.Private)
            {
                fields["symbol"] = "eyeglasses";
                fields["accent"] = "indigo";
                var browsing = fields["browsingPreferences"]!.AsObject();
                browsing["selectedSearchProviderID"] = "duckDuckGo";
                browsing["searchProvider"] = "duckDuckGo";
                browsing["currentTabCleanupPolicy"] = "never";
                fields["credentialPreferences"] = new JsonObject
                {
                    ["isEnabled"] = false, ["syncsCrestPasswordsWithICloud"] = false,
                    ["alsoOffersSaveToSystemPasswords"] = false
                };
            }
            spaces.Add(new(fields, sections));
            metadata["selectedSpaceID"] = supplied["id"]!.DeepClone();
            created = id;
        }
        else if (operation == "space.reorder")
        {
            spaces = SpaceOrganizationPolicy.Move(spaces,
                args["offsets"]!.AsArray().Select(n => n!.GetValue<int>()), args["destination"]!.GetValue<int>()).ToList();
        }
        else
        {
            var id = Id(request["spaceId"]);
            var index = spaces.FindIndex(s => Id(s.Metadata["id"]) == id);
            if (index < 0) throw new BrowserRuleException("unknown_space");
            var space = spaces[index];
            if (Id(request["profileId"]) != Id(space.Metadata["profile"]!["id"]))
                throw new BrowserRuleException("wrong_profile_identity");
            var fields = space.Metadata;
            switch (operation)
            {
                case "space.identity":
                    fields["name"] = SpaceOrganizationPolicy.Name(args["name"]!.GetValue<string>());
                    fields["symbol"] = SpaceOrganizationPolicy.Symbol(args["symbol"]!.GetValue<string>());
                    var accent = args["accent"]!.GetValue<string>();
                    if (accent is not ("indigo" or "orange" or "teal" or "rose")) throw new BrowserRuleException("invalid_accent");
                    fields["accent"] = accent;
                    break;
                case "space.branding":
                    // The native view supplies its rendering vocabulary. Store it
                    // as metadata without reconstructing tabs, history or images.
                    fields["branding"] = args["value"]!.AsObject().DeepClone();
                    break;
                case "space.browsing_preferences":
                    fields["browsingPreferences"] = args["value"]!.AsObject().DeepClone();
                    break;
                case "space.credential_preferences":
                    fields["credentialPreferences"] = args["value"]!.AsObject().DeepClone();
                    break;
                case "space.access":
                    var access = args["value"]!.GetValue<string>();
                    if (access is not ("open" or "deviceOwnerAuthentication")) throw new BrowserRuleException("invalid_access_policy");
                    fields["accessPolicy"] = access;
                    break;
                case "space.default":
                    metadata["defaultSpaceID"] = fields["id"]!.DeepClone();
                    break;
                case "space.saved_expansion":
                    var expanded = args["value"]!.GetValue<bool>();
                    if (fields["isSavedTabsExpanded"]?.GetValue<bool>() != expanded)
                    {
                        fields["isSavedTabsExpanded"] = expanded;
                        fields["savedTabsExpansionModifiedAt"] = request["now"]!.DeepClone();
                    }
                    break;
                case "space.remove":
                    SpaceOrganizationPolicy.RequireRemovable(spaces.Count);
                    spaces.RemoveAt(index);
                    if (Id(metadata["selectedSpaceID"]) == id)
                        metadata["selectedSpaceID"] = spaces[Math.Min(index, spaces.Count - 1)].Metadata["id"]!.DeepClone();
                    if (metadata["defaultSpaceID"] is { } defaultId && Id(defaultId) == id)
                        metadata["defaultSpaceID"] = metadata["selectedSpaceID"]!.DeepClone();
                    break;
                default: throw new BrowserRuleException("unknown_space_command");
            }
        }
        var next = new SessionDocument(metadata, spaces);
        Validate(next);
        var projection = metadata.DeepClone().AsObject();
        projection["spaces"] = new JsonArray(spaces.Select(s =>
        {
            var value = s.Metadata.DeepClone().AsObject();
            foreach (var section in Sections)
                value[section] = new JsonArray(created == Id(s.Metadata["id"])
                    ? s.Sections[section].Select(n => n.DeepClone()).ToArray() : []);
            return (JsonNode)value;
        }).ToArray());
        var output = Encoding.UTF8.GetBytes(new JsonObject { ["session"] = projection }.ToJsonString());
        if (output.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException("session_edit_limit");
        return new NativeSessionCommand(this, expected, next, output);
    }
}
