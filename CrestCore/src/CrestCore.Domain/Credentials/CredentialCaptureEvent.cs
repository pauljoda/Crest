namespace CrestCore.Domain;

/// A credential form observation, or `Filled` when the native layer finished
/// filling a saved credential into the page.
public enum CredentialCaptureEvent { Username, Focus, Submit, DocumentState, Filled }
