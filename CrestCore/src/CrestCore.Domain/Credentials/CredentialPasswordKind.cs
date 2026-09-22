namespace CrestCore.Domain;

/// Whether a password field asks for the account's current password or for a
/// new one, as the form classifier reported it.
public enum CredentialPasswordKind { Current, New }
