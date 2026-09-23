namespace CrestCore.Contracts;

/// What the platform knows about a download before its risk is judged.
///
/// `SanitizedFilename` is the platform's file-system-safe name. The three type
/// facts come from the platform's type registry: whether the filename's
/// extension and the declared MIME type name code-running types, and whether
/// the two types are related (null when either type is unknown).
public sealed record DownloadRiskFacts(string SuggestedFilename, string SanitizedFilename, string? MimeType,
    bool ExtensionRunsCode, bool MimeTypeRunsCode, bool? TypesRelated);
