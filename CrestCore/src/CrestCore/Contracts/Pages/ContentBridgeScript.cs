namespace CrestCore.Contracts;

/// A core-owned content bridge script ready for any platform or engine to
/// inject into an isolated world.
public sealed record ContentBridgeScript(string Source, string HandlerName, bool MainFrameOnly);
