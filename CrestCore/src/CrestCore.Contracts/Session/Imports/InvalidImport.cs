namespace CrestCore.Contracts;

/// The import's Spaces or choices cannot be read, for the reason `Flaw` names.
public sealed record InvalidImport(ImportFlaw Flaw) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t read the Spaces to import.";

    #endregion
}
