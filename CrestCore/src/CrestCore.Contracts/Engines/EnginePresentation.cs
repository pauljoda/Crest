namespace CrestCore.Contracts;

/// What an engine binding tells the platform directly about one of its pages:
/// presentation that no browser rule reads, such as how many matches a find
/// counted, and the results of requests that finish later. The core never
/// sees these.
public abstract record EnginePresentation;
