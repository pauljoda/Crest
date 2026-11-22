namespace CrestCore.Contracts;

#region Queries

/// The session an import would leave: `Session`, the tabs it would place from
/// its Spaces, and the workspace's own tabs that would take a new identity.
public sealed record ImportedWorkspace(SessionState Session, IReadOnlyList<ImportedTab> Imported, IReadOnlyList<TabCopied> Copied);

#endregion

#region Rejections

/// The import's Spaces or choices cannot be read, for the reason `Flaw` names.
public sealed record InvalidImport(ImportFlaw Flaw) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t read the Spaces to import.";

    #endregion
}

/// Why the core cannot read an import.
public enum ImportFlaw {
    /// Its Spaces are not Spaces in the stored format.
    Unreadable,
    /// A Space holds a split whose tabs are not one run of open tabs, which
    /// repair would rewrite.
    MalformedSplit,
    /// A choice names a Space the import does not bring, a Space it brings has
    /// no choice, or two of its Spaces share an identity, so a choice cannot
    /// tell them apart.
    UnpairedChoices
}

/// The core could not work out the import its Spaces and choices ask for: one
/// of its steps broke on something they hold, which `Cause` names by the
/// exception and the methods it went through, never by anything the Spaces
/// hold, so the app can write it to its log. Nothing changed.
public sealed record UnpreparedImport(string Cause) : Rejection {
    #region Static Variables

    /// The most methods `Cause` names.
    private const int MaximumFrames = 8;

    #endregion

    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t prepare this import.";

    #endregion

    #region Actions - Naming

    /// The refusal for an import `error` broke: its type, then the type and
    /// method of each frame it went through, innermost first. A stack trace
    /// names methods and their parameter types alone; the exception's message
    /// is left out, since it may quote a value.
    internal static UnpreparedImport Of(Exception error) {
        ArgumentNullException.ThrowIfNull(error);
        var frames = (error.StackTrace ?? "").Split('\n')
            .Select(line => line.Trim())
            .Where(line => line.StartsWith("at ", StringComparison.Ordinal))
            .Select(line => line[3..].Split('(')[0].Split('.'))
            .Select(parts => string.Join('.', parts.TakeLast(2)))
            .Take(MaximumFrames);
        return new(string.Join(" < ", [error.GetType().Name, .. frames]));
    }

    #endregion
}

/// A reviewed import includes none of its Spaces.
public sealed record NoIncludedSpaces : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Choose at least one Space to import.";

    #endregion
}

/// Another Space already uses the profile `ProfileId`, and a profile belongs
/// to one Space.
public sealed record ProfileInUse(Guid ProfileId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Another Space already uses this Space’s browsing data.";

    #endregion
}

#endregion

#region Models

/// A tab an import placed, `TabId`, and the tab it came from: `SourceTabId`,
/// open or archived, of the import's Space at position `Source` among its
/// Spaces.
public sealed record ImportedTab(Guid TabId, int Source, Guid SourceTabId);

/// A reviewed tab that moves to `Placement`.
public sealed record TabPlacementChoice(Guid TabId, TabPlacement Placement);

#endregion
