using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the manual-setup and onboarding policy operations. They
/// match the native onboarding models' case names.
internal static class SetupCodes {
    #region Actions - Decoding

    public static OnboardingEntryPoint EntryPoint(string value) => value switch {
        "firstRun" => OnboardingEntryPoint.FirstRun,
        "importBrowser" => OnboardingEntryPoint.ImportBrowser,
        "manualSetup" => OnboardingEntryPoint.ManualSetup,
        "rerun" => OnboardingEntryPoint.Rerun,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidEntryPoint)
    };

    public static OnboardingSpaceIdentity? Identity(JsonElement request, string field) {
        if (!request.TryGetProperty(field, out var value) || value.ValueKind == JsonValueKind.Null) return null;
        Protocol.Members(value, "spaceID", "profileID");
        return new(Protocol.Id(value, "spaceID"), Protocol.Id(value, "profileID"));
    }

    #endregion

    #region Actions - Encoding

    /// The accent a new draft Space takes: each in turn, then repeating.
    public static string Accent(int number) => SpaceAccent.All[(number - 1) % SpaceAccent.All.Count].Name;

    public static string Outcome(OnboardingCompletion outcome) => outcome switch {
        OnboardingCompletion.Complete => "complete",
        OnboardingCompletion.OpenGuide => "openGuide",
        _ => "sourceChanged"
    };

    /// A new draft Space's suggested name, accent and symbol.
    public static JsonObject SpaceAnswer(int number) => new() {
        ["name"] = ManualSetupPolicy.NewSpaceName(number),
        ["accent"] = Accent(number),
        ["symbol"] = ManualSetupPolicy.NewSpaceSymbol
    };

    public static JsonObject TabAnswer(ManualSetupTab tab) =>
        new() { ["title"] = tab.Title, ["symbol"] = tab.Symbol, ["keepsSavedURL"] = tab.KeepsSavedUrl };

    public static JsonObject ReconcileAnswer(IEnumerable<ManualSetupEntry> entries) => new() {
        ["entries"] = new JsonArray(entries.Select(entry => (JsonNode?)new JsonObject {
            ["draft"] = entry.DraftIndex,
            ["existing"] = entry.ExistingIndex
        }).ToArray())
    };

    public static JsonObject OutcomeAnswer(OnboardingCompletion outcome) => new() { ["outcome"] = Outcome(outcome) };

    public static JsonObject GuideAnswer(bool confirmed) => new() { ["confirmed"] = confirmed };

    #endregion
}
