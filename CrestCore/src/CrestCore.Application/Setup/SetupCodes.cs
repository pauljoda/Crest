using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the manual-setup and onboarding policy operations. They
/// match the native onboarding models' case names.
internal static class SetupCodes {
    #region Variables

    /// New draft Spaces take the accents in this order, then repeat.
    private static readonly string[] Accents = [SpaceAccentCodes.Indigo, SpaceAccentCodes.Orange,
        SpaceAccentCodes.Teal, SpaceAccentCodes.Rose];

    #endregion

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

    public static string Accent(int number) => Accents[(number - 1) % Accents.Length];

    public static string Outcome(OnboardingCompletion outcome) => outcome switch {
        OnboardingCompletion.Complete => "complete",
        OnboardingCompletion.OpenGuide => "openGuide",
        _ => "sourceChanged"
    };

    #endregion
}
