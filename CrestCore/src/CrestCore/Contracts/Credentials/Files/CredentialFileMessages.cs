namespace CrestCore.Contracts;

#region Rejections

/// A password file cannot be imported, for the reason `Flaw` names.
public sealed record InvalidCredentialFile(CredentialFileFlaw Flaw) : Rejection;

#endregion

#region Models

/// Row `RowNumber` of a password file, counting its header as row 1, is left
/// out for the reason `Flaw` names.
public sealed record CredentialRowRejection(int RowNumber, CredentialRowFlaw Flaw);

/// Row `RowNumber` of a password file, counting its header as row 1, imports
/// with `Caution`.
public sealed record CredentialRowWarning(int RowNumber, CredentialRowCaution Caution);

/// How many rows of a password file `Flaw` leaves out.
public sealed record CredentialRowFlawCount(CredentialRowFlaw Flaw, int Count);

#endregion
