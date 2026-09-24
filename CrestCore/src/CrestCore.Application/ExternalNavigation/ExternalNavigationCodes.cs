using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// Wire spellings for the external scheme, link and local-file policy
/// operations. They match the native navigation models' case names.
internal static class ExternalNavigationCodes {
    #region Variables

    /// The longest host a platform-parsed URL may report.
    public const int MaximumUrlHostLength = 1_024;

    #endregion

    #region Actions - Encoding

    public static JsonObject AcceptedAnswer(bool accepted) => new() { ["accepted"] = accepted };

    public static JsonObject DispositionAnswer(ExternalSchemeDisposition disposition) =>
        new() { ["disposition"] = disposition.Name };

    #endregion
}
