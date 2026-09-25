namespace CrestCore.Contracts;

/// What the platform asks a page's engine binding directly, as `EnginePage`
/// does: view work such as going back, finding text or capturing the page,
/// which changes no browser state. The binding answers with a `TAnswer` at
/// once; work that finishes later answers with an `EnginePresentation`. The
/// core never sees these; they share the engine contract so every binding
/// answers the same requests.
public abstract record PageRequest<TAnswer>;
