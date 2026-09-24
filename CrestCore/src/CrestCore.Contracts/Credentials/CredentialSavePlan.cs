namespace CrestCore.Contracts;

/// The save plan for one candidate. `Id` names the existing record an update
/// replaces or an unchanged save leaves alone.
public sealed record CredentialSavePlan(CredentialSavePlanKind Kind, Guid? Id) {
    #region Variables

    /// Only a save that writes to the vault asks the person first.
    public bool RequiresConfirmation => Kind != CredentialSavePlanKind.AlreadyStored;

    #endregion
}
