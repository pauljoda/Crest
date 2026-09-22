namespace CrestCore.Domain;

/// Why a download deserves a warning, and whether the warning must be shown.
public static class DownloadRiskPolicy {
    #region Variables

    private static readonly HashSet<string> DangerousExtensions = new(StringComparer.Ordinal) {
        "app", "application", "bat", "bin", "cmd", "com", "command", "csh", "dmg",
        "exe", "jar", "ksh", "mobileconfig", "mpkg", "msi", "pkg", "ps1", "reg",
        "run", "scpt", "scr", "sh", "tool", "vbs", "workflow", "zsh"
    };

    private static readonly HashSet<string> DangerousMimeTypes = new(StringComparer.Ordinal) {
        "application/x-apple-diskimage",
        "application/x-bat",
        "application/x-executable",
        "application/x-mach-binary",
        "application/x-msdownload",
        "application/x-msi",
        "application/x-powershell",
        "application/x-sh",
        "application/x-shellscript"
    };

    #endregion

    #region Actions - Risk

    public static DownloadRiskAssessment Assess(DownloadRiskFacts facts) {
        ArgumentNullException.ThrowIfNull(facts);
        if (string.IsNullOrEmpty(facts.SanitizedFilename)) throw new BrowserRuleException(BrowserRuleCodes.InvalidDownloadFilename);
        bool extensionIsDangerous = facts.ExtensionRunsCode || DangerousExtensions.Contains(Extension(facts.SanitizedFilename));
        bool mimeIsDangerous = facts.MimeTypeRunsCode
            || facts.MimeType is { } mime && DangerousMimeTypes.Contains(mime.ToLowerInvariant());
        var reasons = new List<DownloadRiskReason>();
        if (extensionIsDangerous || mimeIsDangerous) reasons.Add(DownloadRiskReason.ExecutableOrInstaller);
        if (ContainsDeceptiveCharacters(facts.SuggestedFilename)) reasons.Add(DownloadRiskReason.DeceptiveFilename);
        if ((extensionIsDangerous || mimeIsDangerous) && facts.TypesRelated == false)
            reasons.Add(DownloadRiskReason.DangerousTypeMismatch);
        return new(facts.SanitizedFilename, reasons);
    }

    /// User-initiated installers follow the platform's quarantine and
    /// Gatekeeper flow without an extra browser prompt. Filename deception and
    /// an executable type mismatch remain suspicious regardless of activation.
    public static bool RequiresConfirmation(DownloadRiskAssessment assessment, bool isUserInitiated) {
        ArgumentNullException.ThrowIfNull(assessment);
        if (assessment.Reasons.Contains(DownloadRiskReason.DeceptiveFilename)
            || assessment.Reasons.Contains(DownloadRiskReason.DangerousTypeMismatch)) return true;
        return assessment.Reasons.Contains(DownloadRiskReason.ExecutableOrInstaller) && !isUserInitiated;
    }

    /// Invisible and direction-changing characters can disguise a filename's
    /// real extension, such as `photo.jpg<RLO>gpj.command`.
    public static bool ContainsDeceptiveCharacters(string filename) {
        ArgumentNullException.ThrowIfNull(filename);
        foreach (var rune in filename.EnumerateRunes()) {
            int value = rune.Value;
            if (value == 0x061C || value is >= 0x200B and <= 0x200F || value is >= 0x202A and <= 0x202E
                || value is >= 0x2066 and <= 0x2069 || value == 0xFEFF) return true;
        }
        return false;
    }

    private static string Extension(string filename) {
        int dot = filename.LastIndexOf('.');
        return dot > 0 && dot < filename.Length - 1 ? filename[(dot + 1)..].ToLowerInvariant() : "";
    }

    #endregion
}
