using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// What a new Space is called, followed by its position, in an ordinary and
    /// in a private workspace; a reset private workspace starts over with one.
    private const string NewSpaceName = "Space";
    private const string NewPrivateSpaceName = "Private";

    /// The symbol every private Space wears.
    private const string PrivateSpaceSymbol = "eyeglasses";

    /// A private Space never offers to save or sync passwords.
    private static readonly CredentialPreferences PrivateCredentialPreferences = new(false, false, false);

    #endregion

    #region Actions - Spaces

    /// Whether two sets of deletion intents name the same deletions.
    private static bool SameDeletions(IReadOnlyList<SpaceDeletionState> left, IReadOnlyList<SpaceDeletionState> right) =>
        left.Count == right.Count && left.All(right.Contains);

    private static SpaceDeletionState? PendingDeletion(SessionState value, Guid spaceId) =>
        value.SpaceDeletions.FirstOrDefault(deletion => deletion.SpaceId == spaceId);

    private NativeSessionCommand PrepareSpaceCommand(ulong expected, JsonObject request) {
        var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
        BorrowedCommandRouting.RequireLocal(operation, workspaceKind == BrowserWorkspaceKind.Temporary);
        var args = request["arguments"]!.AsObject();
        var followUp = new WindowFollowUp(IssuingWindow(request));
        var spaces = session.Spaces.ToList();
        var deletions = session.SpaceDeletions.ToList();
        var defaultSpace = session.DefaultSpaceId;
        Guid? created = null;
        if (operation is SessionOperation.SpaceCreate or SessionOperation.SpaceResetPrivate) {
            var template = StoredSessionCodec.DecodeSpace(args["template"]);
            if (operation == SessionOperation.SpaceResetPrivate) {
                if (workspaceKind != BrowserWorkspaceKind.Private) throw new BrowserRuleException(BrowserRuleCodes.NotPrivateWorkspace);
                if (spaces.Any(s => s.Id == template.Id || s.ProfileId == template.ProfileId))
                    throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
                spaces.Clear(); deletions.Clear(); defaultSpace = null;
            }
            if (spaces.Any(s => s.Id == template.Id || s.ProfileId == template.ProfileId))
                throw new BrowserRuleException(BrowserRuleCodes.DuplicateSpaceProfile);
            if (template.History.Count != 0 || template.ArchivedTabs.Count != 0 || template.Folders.Count != 0
                || template.Tabs.Count != 1 || template.Tabs[0].Url is not null)
                throw new BrowserRuleException(BrowserRuleCodes.InvalidNewSpace);
            var space = template with {
                Name = operation == SessionOperation.SpaceResetPrivate ? NewPrivateSpaceName
                    : $"{(workspaceKind == BrowserWorkspaceKind.Private ? NewPrivateSpaceName : NewSpaceName)} {spaces.Count + 1}"
            };
            if (workspaceKind == BrowserWorkspaceKind.Private)
                space = space with {
                    Symbol = PrivateSpaceSymbol,
                    Accent = SpaceAccent.Indigo,
                    BrowsingPreferences = space.BrowsingPreferences with {
                        SelectedSearchProviderId = SearchProvider.DuckDuckGo.Name,
                        CurrentTabCleanup = CurrentTabCleanup.Never
                    },
                    CredentialPreferences = PrivateCredentialPreferences
                };
            spaces.Add(space);
            // A new Space is the one its window shows next, on its only tab.
            followUp.ShowSpace(space.Id).ShowTab(space.Id, space.Tabs[0].Id);
            created = space.Id;
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
            var pending = deletions.FirstOrDefault(deletion => deletion.SpaceId == id);
            if (pending is not null && operation is not (SessionOperation.SpaceDeletionBegin or SessionOperation.SpaceRemove))
                throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
            switch (operation) {
                case SessionOperation.SpaceDeletionBegin:
                    var operationId = Id(args["operationID"]);
                    if (pending is not null) {
                        if (pending.Id != operationId) throw new BrowserRuleException(BrowserRuleCodes.WrongDeletionOperation);
                        break;
                    }
                    SpaceOrganizationPolicy.RequireRemovable(spaces.Count - deletions.Count);
                    deletions.Add(new(operationId, space.Id, space.ProfileId));
                    // The window showing a Space that is going away moves to the
                    // first one that stays.
                    if (followUp.Window?.ShownSpaceId == id)
                        followUp.ShowSpace(spaces.First(s => deletions.All(deletion => deletion.SpaceId != s.Id)).Id);
                    break;
                case SessionOperation.SpaceIdentity:
                    spaces[index] = space with {
                        Name = SpaceOrganizationPolicy.Name(args["name"]!.GetValue<string>()),
                        Symbol = SpaceOrganizationPolicy.Symbol(args["symbol"]!.GetValue<string>()),
                        Accent = StoredSessionCodec.ParseAccent(args["accent"]!.GetValue<string>())
                            ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidAccent)
                    };
                    break;
                case SessionOperation.SpaceBranding:
                    // The native view supplies its rendering vocabulary; the core
                    // applies its range rules to it.
                    spaces[index] = space with { Branding = SpaceBrandingPolicy.Normalize(StoredSessionCodec.DecodeBranding(args["value"])) };
                    break;
                case SessionOperation.SpaceBrowsingPreferences:
                    spaces[index] = space with { BrowsingPreferences = StoredSessionCodec.DecodeBrowsingPreferences(args["value"]) };
                    break;
                case SessionOperation.SpaceSearchProviderUpsert or SessionOperation.SpaceSearchProviderRemove:
                    spaces[index] = space with { BrowsingPreferences = EditSearchProviders(operation, space.BrowsingPreferences, args) };
                    break;
                case SessionOperation.SpaceCredentialPreferences:
                    spaces[index] = space with { CredentialPreferences = StoredSessionCodec.DecodeCredentialPreferences(args["value"]) };
                    break;
                case SessionOperation.SpaceAccess:
                    spaces[index] = space with {
                        AccessPolicy = StoredSessionCodec.ParseAccessPolicy(args["value"]!.GetValue<string>())
                            ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidAccessPolicy)
                    };
                    break;
                case SessionOperation.SpaceDefault:
                    defaultSpace = space.Id;
                    break;
                case SessionOperation.SpaceSavedExpansion:
                    var expanded = args["value"]!.GetValue<bool>();
                    if (space.IsSavedTabsExpanded != expanded)
                        spaces[index] = space with { IsSavedTabsExpanded = expanded, SavedTabsExpansionModifiedAt = Now(request) };
                    break;
                case SessionOperation.SpaceRemove:
                    if (pending is null || pending.Id != Id(args["operationID"]))
                        throw new BrowserRuleException(BrowserRuleCodes.WrongDeletionOperation);
                    SpaceOrganizationPolicy.RequireRemovable(spaces.Count);
                    spaces.RemoveAt(index);
                    deletions.Remove(pending);
                    // The Space that takes the removed one's place is where its
                    // window goes and, when it was the launch Space, the new one.
                    var neighbor = spaces[Math.Min(index, spaces.Count - 1)].Id;
                    if (followUp.Window?.ShownSpaceId == id) followUp.ShowSpace(neighbor);
                    if (defaultSpace == id) defaultSpace = neighbor;
                    break;
                default: throw new BrowserRuleException(BrowserRuleCodes.UnknownSpaceCommand);
            }
        }
        var next = session with { Spaces = spaces.ToArray(), SpaceDeletions = deletions.ToArray(), DefaultSpaceId = defaultSpace };
        Validate(next);
        var projection = StoredSessionCodec.Encode(next with {
            Spaces = spaces.Select(s => created == s.Id ? s : Settings(s)).ToArray()
        });
        return new NativeSessionCommand(this, expected, next, Output(new JsonObject { ["session"] = projection }), followUp: followUp);
    }

    #endregion
}
