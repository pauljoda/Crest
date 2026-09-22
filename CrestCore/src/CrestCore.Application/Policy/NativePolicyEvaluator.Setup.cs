using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public static partial class NativePolicyEvaluator {
    #region Variables

    private const int MaximumSetupUrlLength = 8_192;
    private const int MaximumSetupTitleLength = 4_096;

    #endregion

    #region Actions - Setup

    /// Null when the operation is not a manual-setup or onboarding policy. The
    /// draft itself stays native; these operations admit its edits and decide
    /// what finishing setup does. The workspace import applies the result.
    private static JsonObject? EvaluateSetup(PolicyOperation operation, JsonElement request) {
        switch (operation) {
            case PolicyOperation.SetupSpace:
                Protocol.Members(request, "version", "operation", "draftCount");
                try {
                    int number = ManualSetupPolicy.NewSpaceNumber(request.GetProperty("draftCount").GetInt32());
                    return new() {
                        ["name"] = ManualSetupPolicy.NewSpaceName(number),
                        ["accent"] = SetupCodes.Accent(number),
                        ["symbol"] = ManualSetupPolicy.NewSpaceSymbol
                    };
                } catch (BrowserRuleException error) {
                    // The setup editor explains the limit the person reached.
                    return new() { ["error"] = error.Code };
                }
            case PolicyOperation.SetupTab:
                Protocol.Members(request, "version", "operation", "placement", "existingPinnedCount", "addedPinnedCount",
                    "url", "title");
                try {
                    var tab = ManualSetupPolicy.AdmitTab(
                        TabPlacementCodes.Parse(Protocol.Text(request, "placement", 16)) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlacement),
                        request.GetProperty("existingPinnedCount").GetInt32(), request.GetProperty("addedPinnedCount").GetInt32(),
                        Protocol.Text(request, "url", MaximumSetupUrlLength),
                        Protocol.OptionalText(request, "title", MaximumSetupTitleLength));
                    return new() { ["title"] = tab.Title, ["symbol"] = tab.Symbol, ["keepsSavedURL"] = tab.KeepsSavedUrl };
                } catch (BrowserRuleException error) {
                    return new() { ["error"] = error.Code };
                }
            case PolicyOperation.SetupReconcile: {
                    Protocol.Members(request, "version", "operation", "drafts", "existing");
                    var drafts = new List<ManualSetupDraft>();
                    foreach (var item in request.GetProperty("drafts").EnumerateArray()) {
                        if (drafts.Count >= ManualSetupPolicy.MaximumDrafts) throw new BrowserRuleException(BrowserRuleCodes.SpaceLimitReached);
                        Protocol.Members(item, "id", "isNew");
                        drafts.Add(new(Protocol.Id(item, "id"), item.GetProperty("isNew").GetBoolean()));
                    }
                    var existing = new List<Guid>();
                    foreach (var item in request.GetProperty("existing").EnumerateArray()) {
                        if (existing.Count >= ManualSetupPolicy.MaximumDrafts) throw new BrowserRuleException(BrowserRuleCodes.SpaceLimitReached);
                        existing.Add(Protocol.Id(item));
                    }
                    return new() {
                        ["entries"] = new JsonArray(ManualSetupPolicy.Reconcile(drafts, existing).Select(entry => (JsonNode?)new JsonObject {
                            ["draft"] = entry.DraftIndex,
                            ["existing"] = entry.ExistingIndex
                        }).ToArray())
                    };
                }
            case PolicyOperation.OnboardingCompletion:
                Protocol.Members(request, "version", "operation", "entryPoint", "hasCompletedSetup", "isPrivateBrowsing");
                return new() {
                    ["outcome"] = SetupCodes.Outcome(OnboardingCompletionPolicy.Decide(
                        SetupCodes.EntryPoint(Protocol.Text(request, "entryPoint", 32)),
                        request.GetProperty("hasCompletedSetup").GetBoolean(), request.GetProperty("isPrivateBrowsing").GetBoolean()))
                };
            case PolicyOperation.OnboardingGuide: {
                    Protocol.Members(request, "version", "operation", "target", "originalFirst", "currentFirst",
                        "originalTarget", "currentTarget", "previewFirst", "hasManualPlan", "locked");
                    var target = SetupCodes.Identity(request, "target") ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                    return new() {
                        ["confirmed"] = OnboardingCompletionPolicy.ConfirmsGuide(new(target,
                            SetupCodes.Identity(request, "originalFirst"), SetupCodes.Identity(request, "currentFirst"),
                            SetupCodes.Identity(request, "originalTarget"), SetupCodes.Identity(request, "currentTarget"),
                            SetupCodes.Identity(request, "previewFirst"), request.GetProperty("hasManualPlan").GetBoolean(),
                            request.GetProperty("locked").GetBoolean()))
                    };
                }
            default:
                return null;
        }
    }

    #endregion
}
