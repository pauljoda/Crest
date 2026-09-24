namespace CrestCore.Contracts;

/// Something the core asks one engine binding to do with a page. The core
/// delivers commands in the order it issued them, never while it holds a lock
/// and never on the stack of the report that caused them.
public abstract record EngineCommand;
