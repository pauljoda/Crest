namespace CrestCore.Contracts;

/// Whether a save candidate may still be planned or committed.
public enum CredentialSaveValidity { Accepted, InsecureOrigin, Stale }
