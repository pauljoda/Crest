namespace CrestCore.Domain;

/// Who owns a navigation once its URL scheme is known.
public enum ExternalSchemeDisposition {
    /// The page engine's to load, or to refuse on its own terms.
    Engine,
    /// Neither the engine nor another application may see it.
    Blocked,
    /// Another application owns the scheme; Crest hands it to the system after consent.
    HandOff,
}
