namespace CrestCore.Contracts;

/// Something an engine binding saw happen to one of its pages. A report is
/// never refused: one about a page the core no longer knows changes nothing.
public abstract record EngineEvent;
